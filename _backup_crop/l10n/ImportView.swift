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
    @State private var excludedFuelIndices: Set<Int> = []
    @State private var excludedMaintenanceIndices: Set<Int> = []

    @State private var isParsing = false
    @State private var isImporting = false
    @State private var errorTitle = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingSuccessAlert = false
    @State private var successMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                if isParsing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reading file…")
                        }
                    }
                } else if let importResult {
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
                        .disabled(isImporting)
                }
            }
            .interactiveDismissDisabled(isImporting)
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
            ) { result in
                handleFileSelection(result)
            }
            .alert(errorTitle, isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .alert("Import Complete", isPresented: $showingSuccessAlert) {
                Button("Done") { dismiss() }
            } message: {
                Text(successMessage)
            }
        }
    }

    // MARK: - Sections

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
                let excludedCount = excludedFuelIndices.count + excludedMaintenanceIndices.count
                if excludedCount > 0 {
                    Text("\(excludedCount) flagged as possible duplicates and excluded by default — see below.")
                        .foregroundStyle(.orange)
                }
                if !result.skippedRows.isEmpty {
                    Text("\(result.skippedRows.count) row\(result.skippedRows.count == 1 ? "" : "s") couldn't be read and won't be imported — see below.")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(result.vehicleNames, id: \.self) { name in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Picker("", selection: Binding(
                            get: { mapping(for: name) },
                            set: { updateMapping(name, to: $0) }
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
                Text("For each vehicle found in the file, choose whether to add its history to an existing vehicle or create a new one. A vehicle whose name matches one you already have is matched automatically.")
            }

            duplicatesSection(result)
            warningsSection(result)
            skippedRowsSection(result)

            Section {
                Button {
                    performImport(result)
                } label: {
                    HStack {
                        Spacer()
                        if isImporting {
                            ProgressView()
                        } else {
                            Text("Import").fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                // Disabled while running so a second tap can't import twice.
                .disabled(isImporting)

                Button("Choose a Different File") {
                    resetToStart()
                }
                .disabled(isImporting)
            }
        }
    }

    @ViewBuilder
    private func duplicatesSection(_ result: ImportResult) -> some View {
        let flaggedFuel = result.fuelEntries.indices.filter { result.fuelEntries[$0].isPossibleDuplicate }
        let flaggedMaintenance = result.maintenanceEntries.indices.filter { result.maintenanceEntries[$0].isPossibleDuplicate }

        if !flaggedFuel.isEmpty || !flaggedMaintenance.isEmpty {
            Section {
                ForEach(flaggedFuel, id: \.self) { index in
                    let entry = result.fuelEntries[index]
                    Toggle(isOn: Binding(
                        get: { !excludedFuelIndices.contains(index) },
                        set: { include in
                            if include { excludedFuelIndices.remove(index) } else { excludedFuelIndices.insert(index) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) — \(entry.mileage.formatted()) mi")
                                .font(.subheadline)
                            Text("\(entry.gallons.formatted(.number.precision(.fractionLength(1)))) gal  •  \(entry.vehicleName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let reason = entry.duplicateReason {
                                Text(reason.description)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                ForEach(flaggedMaintenance, id: \.self) { index in
                    let entry = result.maintenanceEntries[index]
                    Toggle(isOn: Binding(
                        get: { !excludedMaintenanceIndices.contains(index) },
                        set: { include in
                            if include { excludedMaintenanceIndices.remove(index) } else { excludedMaintenanceIndices.insert(index) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) — \(entry.mileage.formatted()) mi")
                                .font(.subheadline)
                            Text("\(entry.title)  •  \(entry.vehicleName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let reason = entry.duplicateReason {
                                Text(reason.description)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("Possible Duplicates")
            } footer: {
                Text("These entries match another row in this file, or a record already saved on the vehicle they're going to. Excluded from import by default; turn one back on if it's actually a separate, legitimate entry.")
            }
        }
    }

    /// Entries that will be imported but have something worth checking.
    @ViewBuilder
    private func warningsSection(_ result: ImportResult) -> some View {
        let fuelWithWarnings = result.fuelEntries.filter { !$0.allWarnings.isEmpty && !$0.isPossibleDuplicate }
        let maintenanceWithWarnings = result.maintenanceEntries.filter { !$0.allWarnings.isEmpty && !$0.isPossibleDuplicate }
        let total = fuelWithWarnings.count + maintenanceWithWarnings.count

        if total > 0 {
            Section {
                DisclosureGroup("\(total) entr\(total == 1 ? "y" : "ies") to review") {
                    ForEach(fuelWithWarnings.prefix(200), id: \.sourceRow) { entry in
                        warningRow(row: entry.sourceRow, summary: "Fuel-up, \(entry.date.formatted(date: .abbreviated, time: .omitted))", warnings: entry.allWarnings)
                    }
                    ForEach(maintenanceWithWarnings.prefix(200), id: \.sourceRow) { entry in
                        warningRow(row: entry.sourceRow, summary: "\(entry.title), \(entry.date.formatted(date: .abbreviated, time: .omitted))", warnings: entry.allWarnings)
                    }
                }
            } header: {
                Text("Needs Review")
            } footer: {
                Text("These will be imported. Each one has something that looked off, like a missing value that was filled in or an odometer reading that doesn't line up. You can edit them after importing.")
            }
        }
    }

    private func warningRow(row: Int, summary: String, warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Row \(row): \(summary)")
                .font(.subheadline)
            ForEach(warnings, id: \.self) { warning in
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func skippedRowsSection(_ result: ImportResult) -> some View {
        if !result.skippedRows.isEmpty {
            Section {
                DisclosureGroup("\(result.skippedRows.count) row\(result.skippedRows.count == 1 ? "" : "s") not imported") {
                    ForEach(result.skippedRows.prefix(200)) { skipped in
                        Text("Row \(skipped.row): \(skipped.reason)")
                            .font(.caption)
                    }
                }
            } header: {
                Text("Couldn't Read")
            } footer: {
                Text("Row numbers match the file as opened in a spreadsheet app, so you can find and fix these in the original file.")
            }
        }
    }

    // MARK: - Vehicle mapping

    /// A vehicle in the file whose name matches an existing vehicle's
    /// nickname (ignoring case and extra spaces) defaults to that vehicle,
    /// so importing the same file twice doesn't create a duplicate vehicle
    /// with a full copy of its history.
    private func defaultMapping(for name: String) -> VehicleMappingChoice {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = existingVehicles.first(where: {
            $0.nickname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key
        }) {
            return .existing(match)
        }
        return .createNew
    }

    private func mapping(for name: String) -> VehicleMappingChoice {
        vehicleMappings[name] ?? defaultMapping(for: name)
    }

    private func updateMapping(_ name: String, to choice: VehicleMappingChoice) {
        vehicleMappings[name] = choice
        reviewAgainstMappings()
    }

    /// Re-checks every entry against the vehicles it's mapped to: duplicates
    /// of records already saved there, and the same date and odometer rules
    /// manual entry uses. Exclusions are reset to the flagged set each time.
    private func reviewAgainstMappings() {
        guard let current = importResult else { return }
        var destinations: [String: Vehicle] = [:]
        for name in current.vehicleNames {
            if case .existing(let vehicle) = mapping(for: name) {
                destinations[name] = vehicle
            }
        }
        let reviewed = FuellyImporter.review(current, destinations: destinations)
        importResult = reviewed
        excludedFuelIndices = Set(reviewed.fuelEntries.indices.filter { reviewed.fuelEntries[$0].isPossibleDuplicate })
        excludedMaintenanceIndices = Set(reviewed.maintenanceEntries.indices.filter { reviewed.maintenanceEntries[$0].isPossibleDuplicate })
    }

    // MARK: - File handling

    /// Tries the encodings real-world CSV files arrive in: UTF-16 when the
    /// file says so (Excel's "Unicode Text"), then UTF-8, then Windows-1252
    /// (Excel on Windows saving "CSV" with accented characters).
    private func decodeText(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
    }

    private func showError(_ title: String, _ message: String) {
        errorTitle = title
        errorMessage = message
        showingError = true
    }

    private func handleFileSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if didAccess { url.stopAccessingSecurityScopedResource() }

            guard let data else {
                showError("Couldn't Open File", "Roadworthy couldn't open that file. If it's stored in iCloud Drive or another cloud service, make sure it has finished downloading, then try again.")
                return
            }
            guard let text = decodeText(data) else {
                showError("Couldn't Read File", "That file isn't in a text format Roadworthy can read. Export it from \(selectedSource.rawValue) again as a CSV file.")
                return
            }

            // Show "Reading file…" before parsing starts. Parsing still runs
            // on the main actor (the importer uses model types and helpers
            // that are main-actor isolated in this project), but the brief
            // pause lets the progress indicator appear first.
            isParsing = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                let parsed = FuellyImporter.parse(csvText: text)
                isParsing = false

                if let fileError = parsed.fileError {
                    showError("Couldn't Read File", fileError)
                    return
                }
                importResult = parsed
                vehicleMappings = [:]
                reviewAgainstMappings()
            }
        case .failure:
            showError("Couldn't Open File", "Roadworthy couldn't open that file. Please try again.")
        }
    }

    private func resetToStart() {
        importResult = nil
        vehicleMappings = [:]
        excludedFuelIndices = []
        excludedMaintenanceIndices = []
    }

    // MARK: - Import

    private func performImport(_ result: ImportResult) {
        guard !isImporting else { return }
        isImporting = true

        var vehiclesByName: [String: Vehicle] = [:]
        for name in result.vehicleNames {
            switch mapping(for: name) {
            case .createNew:
                vehiclesByName[name] = createVehicle(named: name, in: result)
            case .existing(let vehicle):
                vehiclesByName[name] = vehicle
            }
        }

        var fuelCount = 0
        for (index, entry) in result.fuelEntries.enumerated() {
            guard !excludedFuelIndices.contains(index) else { continue }
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
        for (index, entry) in result.maintenanceEntries.enumerated() {
            guard !excludedMaintenanceIndices.contains(index) else { continue }
            guard let vehicle = vehiclesByName[entry.vehicleName] else { continue }
            let record = MaintenanceRecord(
                type: entry.type,
                title: entry.title,
                date: entry.date,
                mileage: entry.mileage,
                cost: entry.cost,
                shopName: entry.shopName,
                notes: entry.notes
            )
            record.vehicle = vehicle
            context.insert(record)
            if entry.mileage > vehicle.currentMileage {
                vehicle.currentMileage = entry.mileage
            }
            maintenanceCount += 1
        }

        // Save explicitly so a failure is reported instead of being lost to
        // autosave after "Import Complete" has already been shown.
        do {
            try context.save()
        } catch {
            context.rollback()
            isImporting = false
            showError("Import Failed", "Nothing was imported. The data couldn't be saved (\((error as NSError).domain) \((error as NSError).code)). Please try again, and contact support if it keeps happening.")
            return
        }

        Haptics.success()
        var message = "Imported \(fuelCount) fuel-up\(fuelCount == 1 ? "" : "s") and \(maintenanceCount) maintenance record\(maintenanceCount == 1 ? "" : "s")."
        let skipped = result.skippedRows.count
        if skipped > 0 {
            message += " \(skipped) row\(skipped == 1 ? " was" : "s were") skipped because they couldn't be read."
        }
        successMessage = message
        importResult = nil
        isImporting = false
        showingSuccessAlert = true
    }

    /// Fuelly's vehicle names are free text like "2019 4Runner TRD" — this
    /// makes a best-effort guess at Year/Make/Model, which the person can
    /// refine afterward in Edit Vehicle. With no year in the name, the year
    /// of the vehicle's earliest entry is used instead of the current year,
    /// so imported history doesn't fail the model-year date check.
    private func createVehicle(named name: String, in result: ImportResult) -> Vehicle {
        let year = FuellyImporter.suggestedModelYear(forVehicle: name, in: result)
        var remainder = name
        if FuellyImporter.leadingYear(in: name) != nil {
            let words = name.split(separator: " ", maxSplits: 1)
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
