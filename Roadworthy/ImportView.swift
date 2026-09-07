import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// How a detected vehicle name from an import file should be handled —
/// either matched to a vehicle that already exists in Roadworthy, or used
/// to create a brand new one.
private enum VehicleMappingChoice: Hashable {
    case createNew
    case existing(Vehicle)
}

struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.nickname) private var existingVehicles: [Vehicle]

    @State private var selectedSource: ImportSource = .fuelly
    @State private var showingFilePicker = false
    @State private var importResult: ImportResult?
    @State private var vehicleMappings: [String: VehicleMappingChoice] = [:]
    @State private var showingParseError = false
    @State private var showingSuccessAlert = false
    @State private var successMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                if let importResult {
                    resultsSection(importResult)
                } else {
                    sourceSection
                }
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text]
            ) { result in
                handleFileSelection(result)
            }
            .alert("Couldn't Read File", isPresented: $showingParseError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This doesn't look like a valid \(selectedSource.rawValue) export. Double check you selected the right file.")
            }
            .alert("Import Complete", isPresented: $showingSuccessAlert) {
                Button("Done") { dismiss() }
            } message: {
                Text(successMessage)
            }
        }
    }

    private var sourceSection: some View {
        Group {
            Section {
                Picker("Importing From", selection: $selectedSource) {
                    ForEach(ImportSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
            } footer: {
                Text("More apps coming soon.")
            }

            Section {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Choose Export File", systemImage: "doc.badge.plus")
                }
            } footer: {
                Text("Export your data from \(selectedSource.rawValue) first (usually found in its Settings or Account menu), then select that file here.")
            }
        }
    }

    private func resultsSection(_ result: ImportResult) -> some View {
        Group {
            Section {
                Text("Found \(result.fuelEntries.count) fuel-up\(result.fuelEntries.count == 1 ? "" : "s") and \(result.maintenanceEntries.count) maintenance record\(result.maintenanceEntries.count == 1 ? "" : "s") across \(result.vehicleNames.count) vehicle\(result.vehicleNames.count == 1 ? "" : "s").")
            }

            Section {
                ForEach(result.vehicleNames, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Picker("", selection: Binding(
                            get: { vehicleMappings[name] ?? .createNew },
                            set: { vehicleMappings[name] = $0 }
                        )) {
                            Text("Create New Vehicle").tag(VehicleMappingChoice.createNew)
                            ForEach(existingVehicles) { vehicle in
                                Text(vehicle.displayName).tag(VehicleMappingChoice.existing(vehicle))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
            } header: {
                Text("Match Vehicles")
            } footer: {
                Text("For each vehicle found in the file, choose whether to add its history to an existing vehicle or create a new one.")
            }

            Section {
                Button {
                    performImport(result)
                } label: {
                    Text("Import")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func handleFileSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
                showingParseError = true
                return
            }
            let parsed = FuellyImporter.parse(csvText: text)
            if parsed.vehicleNames.isEmpty {
                showingParseError = true
                return
            }
            importResult = parsed
        case .failure:
            showingParseError = true
        }
    }

    private func performImport(_ result: ImportResult) {
        var vehiclesByName: [String: Vehicle] = [:]
        for name in result.vehicleNames {
            switch vehicleMappings[name] ?? .createNew {
            case .createNew:
                vehiclesByName[name] = createVehicle(named: name)
            case .existing(let vehicle):
                vehiclesByName[name] = vehicle
            }
        }

        var fuelCount = 0
        for entry in result.fuelEntries {
            guard let vehicle = vehiclesByName[entry.vehicleName] else { continue }
            let log = FuelLog(
                date: entry.date,
                mileage: entry.mileage,
                gallons: entry.gallons,
                pricePerGallon: entry.pricePerGallon,
                isFullTank: entry.isFullTank,
                totalCost: entry.totalCost,
                fuelGrade: entry.fuelGrade,
                stationName: entry.stationName,
                paymentMethod: entry.paymentMethod,
                notes: entry.notes
            )
            log.vehicle = vehicle
            context.insert(log)
            if entry.mileage > vehicle.currentMileage {
                vehicle.currentMileage = entry.mileage
            }
            fuelCount += 1
        }

        var maintenanceCount = 0
        for entry in result.maintenanceEntries {
            guard let vehicle = vehiclesByName[entry.vehicleName] else { continue }
            let record = MaintenanceRecord(
                type: entry.type,
                title: entry.title,
                date: entry.date,
                mileage: entry.mileage,
                cost: entry.cost,
                notes: entry.notes
            )
            record.vehicle = vehicle
            context.insert(record)
            if entry.mileage > vehicle.currentMileage {
                vehicle.currentMileage = entry.mileage
            }
            maintenanceCount += 1
        }

        Haptics.success()
        successMessage = "Imported \(fuelCount) fuel-up\(fuelCount == 1 ? "" : "s") and \(maintenanceCount) maintenance record\(maintenanceCount == 1 ? "" : "s")."
        showingSuccessAlert = true
    }

    /// Fuelly's vehicle names are free text like "2019 4Runner TRD" — this
    /// makes a best-effort guess at Year/Make/Model, which the person can
    /// refine afterward in Edit Vehicle.
    private func createVehicle(named name: String) -> Vehicle {
        var year = Calendar.current.component(.year, from: .now)
        var remainder = name

        let words = name.split(separator: " ", maxSplits: 1)
        if let first = words.first, first.count == 4, let parsedYear = Int(first), parsedYear > 1900 && parsedYear < 2100 {
            year = parsedYear
            remainder = words.count > 1 ? String(words[1]) : ""
        }

        let parts = remainder.split(separator: " ", maxSplits: 1)
        let make = parts.first.map(String.init) ?? ""
        let model = parts.count > 1 ? String(parts[1]) : ""

        let vehicle = Vehicle(nickname: name, make: make, model: model, year: year)
        context.insert(vehicle)
        return vehicle
    }
}
