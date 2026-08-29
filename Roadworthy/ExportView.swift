import SwiftUI

private struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ExportView: View {
    let vehicle: Vehicle
    @State private var fileToShare: ExportFile?
    @State private var exportError: String?
    @AppStorage("businessMileageRate") private var mileageRate: Double = 0.76

    var body: some View {
        List {
            Section {
                Button {
                    exportPDF(named: "Maintenance History") {
                        ExportGenerator.maintenanceHistoryPDF(vehicle: vehicle)
                    }
                } label: {
                    Label("Export as PDF", systemImage: "doc.richtext")
                }
                Button {
                    exportCSV(named: "Maintenance History") {
                        CSVGenerator.maintenanceHistoryCSV(vehicle: vehicle)
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
                Button {
                    exportPDF(named: "Business Mileage Log") {
                        ExportGenerator.businessMileageLogPDF(vehicle: vehicle, rate: mileageRate)
                    }
                } label: {
                    Label("Business Mileage Log (PDF)", systemImage: "map")
                }
            } header: {
                Text("Business Mileage")
            } footer: {
                Text("Formatted for tax purposes — trip-by-trip log with business purpose notes and the estimated deduction, ready to hand to an accountant or keep on file.")
            }

            Section {
                Button {
                    exportPDF(named: "Vehicle History Report") {
                        ExportGenerator.fullVehicleHistoryPDF(vehicle: vehicle)
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
        .navigationTitle("Export & Share")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $fileToShare) { file in
            ShareSheet(activityItems: [file.url])
        }
        .alert("Couldn't Create File", isPresented: .constant(exportError != nil), presenting: exportError) { _ in
            Button("OK") { exportError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func exportPDF(named baseName: String, data: () -> Data) {
        writeAndShare(filename: "\(vehicle.displayName) \(baseName).pdf", contents: data())
    }

    private func exportCSV(named baseName: String, content: () -> String) {
        writeAndShare(filename: "\(vehicle.displayName) \(baseName).csv", contents: Data(content().utf8))
    }

    private func writeAndShare(filename: String, contents: Data) {
        let sanitized = filename.replacingOccurrences(of: "/", with: "-")
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(sanitized)
        do {
            try contents.write(to: fileURL, options: .atomic)
            fileToShare = ExportFile(url: fileURL)
        } catch {
            exportError = "Something went wrong while creating the file. Please try again."
        }
    }
}
