import SwiftUI

private struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ExportView: View {
    let vehicle: Vehicle
    @State private var fileToShare: ExportFile?
    @State private var exportError: String?
    @State private var isGenerating = false
    /// 0 means "All Years".
    @State private var taxYear = Calendar.current.component(.year, from: .now)
    @AppStorage("businessMileageRate") private var mileageRate: Double = 0.76
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .miles

    private var tripYears: [Int] { ExportGenerator.tripYears(for: vehicle) }

    var body: some View {
        List {
            if isGenerating {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing file…")
                    }
                }
            }

            Section {
                Button {
                    export(baseName: "Maintenance History", fileExtension: "pdf") {
                        ExportGenerator.maintenanceHistoryPDF(vehicle: vehicle, unit: distanceUnit)
                    }
                } label: {
                    Label("Export as PDF", systemImage: "doc.richtext")
                }
                Button {
                    export(baseName: "Maintenance History", fileExtension: "csv") {
                        // The UTF-8 byte-order mark tells Excel the file is
                        // UTF-8. Without it, accented and non-Latin text
                        // (French, Spanish, Chinese, Hindi) shows as garbled
                        // characters. Roadworthy's importer strips it.
                        Data([0xEF, 0xBB, 0xBF]) + Data(CSVGenerator.maintenanceHistoryCSV(vehicle: vehicle, unit: distanceUnit).utf8)
                    }
                } label: {
                    Label("Export as CSV", systemImage: "tablecells")
                }
            } header: {
                Text("Maintenance History")
            } footer: {
                Text("PDF is easy to read or hand to a mechanic. CSV opens in Excel, Numbers, or Google Sheets for your own analysis.")
            }

            Section {
                Picker("Tax Year", selection: $taxYear) {
                    ForEach(yearOptions, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                    Text("All Years").tag(0)
                }
                Button {
                    let year = taxYear == 0 ? nil : taxYear
                    let suffix = year.map { " \($0)" } ?? " All Years"
                    export(baseName: "Business Mileage Log\(suffix)", fileExtension: "pdf") {
                        ExportGenerator.businessMileageLogPDF(vehicle: vehicle, rate: mileageRate, unit: distanceUnit, taxYear: year)
                    }
                } label: {
                    Label("Business Mileage Log (PDF)", systemImage: "map")
                }
            } header: {
                Text("Business Mileage")
            } footer: {
                Text("Formatted for tax purposes — trip-by-trip log with business purpose notes. Choose a single tax year to include an estimated deduction, since the IRS rate changes by year.")
            }

            Section {
                Button {
                    export(baseName: "Vehicle History Report", fileExtension: "pdf") {
                        ExportGenerator.fullVehicleHistoryPDF(vehicle: vehicle, unit: distanceUnit)
                    }
                } label: {
                    Label("Full Vehicle History Report (PDF)", systemImage: "doc.text.image")
                }
            } header: {
                Text("Full Vehicle History")
            } footer: {
                Text("Includes vehicle info, maintenance, fuel, expenses, reminders, and saved specs in one document — useful for handing over at resale.")
            }
        }
        .disabled(isGenerating)
        .navigationTitle("Export & Share")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $fileToShare, onDismiss: removeSharedFiles) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert(
            "Couldn't Create File",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    /// The current year is always offered, plus every year that has trips.
    private var yearOptions: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        return Array(Set(tripYears + [current])).sorted(by: >)
    }

    // MARK: - File creation

    /// Shows "Preparing file…" before generating. Generation still runs on
    /// the main actor, because it reads SwiftData models directly, but the
    /// brief pause lets the indicator appear first. Large reports are now
    /// much lighter (photos are downsampled), so the wait is shorter too.
    private func export(baseName: String, fileExtension: String, contents: @escaping () -> Data) {
        guard !isGenerating else { return }
        isGenerating = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            let data = contents()
            isGenerating = false
            writeAndShare(filename: Self.sanitizedFilename("\(vehicle.displayName) \(baseName)", fileExtension: fileExtension), contents: data)
        }
    }

    /// Removes characters that aren't allowed or cause trouble in filenames
    /// on iOS, macOS, and Windows, and keeps the name a reasonable length.
    /// Previously only "/" was replaced, so a nickname with ":" or a line
    /// break made the export fail.
    static func sanitizedFilename(_ name: String, fileExtension: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        var base = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        while base.hasPrefix(".") { base.removeFirst() }
        if base.count > 100 { base = String(base.prefix(100)).trimmingCharacters(in: .whitespaces) }
        if base.isEmpty { base = "Roadworthy Export" }
        return "\(base).\(fileExtension)"
    }

    /// Files are written to a Roadworthy-specific temp folder so they can be
    /// cleaned up once the share sheet closes.
    private static var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
    }

    private func writeAndShare(filename: String, contents: Data) {
        let directory = Self.exportDirectory
        let fileURL = directory.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try contents.write(to: fileURL, options: .atomic)
            fileToShare = ExportFile(url: fileURL)
        } catch {
            let nsError = error as NSError
            exportError = "The file couldn't be saved (\(nsError.domain) \(nsError.code)). If your device is low on storage, free up some space and try again."
        }
    }

    private func removeSharedFiles() {
        try? FileManager.default.removeItem(at: Self.exportDirectory)
    }
}
