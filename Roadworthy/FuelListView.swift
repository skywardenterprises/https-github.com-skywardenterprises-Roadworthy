import SwiftUI
import SwiftData

struct FuelListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .miles
    @State private var logToEdit: FuelLog?
    @State private var pendingDeletion: [FuelLog] = []

    private var sortedLogs: [FuelLog] {
        vehicle.fuelLogs.sorted { $0.date > $1.date }
    }

    // Average of every plausible full-tank-to-full-tank interval — kept
    // consistent with the Overview screen's calculation. Implausible
    // intervals (a typo, a missed fill-up, etc.) are excluded here and
    // surfaced separately in the Data Quality section below instead.
    private var averageMPG: Double? {
        let plausible = MPGCalculator.plausibleIntervals(for: vehicle.fuelLogs).map(\.mpg)
        return plausible.isEmpty ? nil : plausible.reduce(0, +) / Double(plausible.count)
    }
    private var flaggedIntervals: [MPGInterval] {
        MPGCalculator.flaggedIntervals(for: vehicle.fuelLogs)
    }

    var body: some View {
        Group {
            if sortedLogs.isEmpty {
                ContentUnavailableView(
                    "No Fill-Ups Yet",
                    systemImage: "fuelpump.fill",
                    description: Text("Log your first fill-up and watch your MPG trends come to life in Reports.")
                )
            } else {
                List {
                    if let averageMPG {
                        Section {
                            LabeledContent("Average MPG", value: averageMPG.formatted(.number.precision(.fractionLength(1))))
                        }
                    }
                    if !flaggedIntervals.isEmpty {
                        Section {
                            ForEach(flaggedIntervals) { interval in
                                Button {
                                    logToEdit = interval.endLog
                                } label: {
                                    flaggedIntervalRow(interval)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Ignore") {
                                        ignoreInterval(interval)
                                    }
                                    .tint(.secondary)
                                }
                            }
                        } header: {
                            Text("Data Quality")
                        } footer: {
                            Text("These intervals calculated an unrealistic MPG, usually from a typo, a missed fill-up, or a fill-up marked full/partial incorrectly. Tap one to fix it, or swipe to ignore the warning — they're excluded from Average MPG either way.")
                        }
                    }
                    Section {
                        ForEach(sortedLogs) { log in
                            Button {
                                logToEdit = log
                            } label: {
                                logRow(log)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                        .onDelete { offsets in pendingDeletion = offsets.map { sortedLogs[$0] } }
                    }
                }
            }
        }
        .navigationTitle("Fuel")
        .navigationBarTitleDisplayMode(.inline)
        .confirmDeletion(of: $pendingDeletion, noun: "fuel log") { deleteLogs($0) }
        .sheet(item: $logToEdit) { log in
            AddEditFuelView(vehicle: vehicle, log: log)
        }
    }

    private func flaggedIntervalRow(_ interval: MPGInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\(interval.mpg.formatted(.number.precision(.fractionLength(1)))) MPG calculated")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            Text("\(interval.startLog.date.formatted(date: .abbreviated, time: .omitted)) → \(interval.endLog.date.formatted(date: .abbreviated, time: .omitted))  •  \(interval.milesDriven.formatted()) mi on \(interval.gallonsUsed.formatted(.number.precision(.fractionLength(1)))) gal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func logRow(_ log: FuelLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(log.gallons.formatted(.number.precision(.fractionLength(1)))) gal")
                    .font(.headline)
                if log.fuelGrade != .regular {
                    Text(log.fuelGrade.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                if log.receiptPhotoData != nil {
                    Image(systemName: "paperclip")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(log.totalCost, format: .currency(code: "USD"))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(log.date.formatted(date: .abbreviated, time: .omitted))
                Text("•")
                Text(formattedDistance(log.mileage, unit: distanceUnit))
                Text("•")
                Text("\(log.pricePerGallon, format: .currency(code: "USD"))/gal")
                if !log.isFullTank {
                    Text("• partial")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !log.stationName.isEmpty {
                Text(log.stationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func ignoreInterval(_ interval: MPGInterval) {
        interval.endLog.mpgWarningIgnored = true
        Haptics.tap()
    }

    private func deleteLogs(_ logs: [FuelLog]) {
        for log in logs {
            context.delete(log)
        }
        Haptics.delete()
    }
}

struct AddEditFuelView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .miles

    // Every fuel log across every vehicle, most recent first — used to
    // build the Station Name autocomplete suggestions. The same gas
    // station serves whichever car you're driving, so this isn't scoped
    // to just the current vehicle.
    @Query(sort: \FuelLog.date, order: .reverse) private var allFuelLogs: [FuelLog]

    private var stationNameHistory: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for log in allFuelLogs {
            let name = log.stationName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(name)
        }
        return result
    }

    // If editing an existing log, pass it in. Nil means "creating new".
    var log: FuelLog?

    @State private var date = Date.now
    @State private var mileageText = ""
    @State private var fuelGrade: FuelGrade = .regular
    @State private var gallonsText = ""
    @State private var priceText = ""
    @State private var totalCostText = ""
    @State private var isFullTank = true
    @State private var stationName = ""
    @State private var paymentMethod: FuelPaymentMethod = .creditCard
    @State private var defAdded = false
    @State private var defAmountText = ""
    @State private var notes = ""
    @State private var receiptPhotoData: Data?
    @State private var isLoadingPhoto = false

    @State private var showingValidationAlert = false
    @State private var validationTitle = ""
    @State private var validationMessage = ""
    @State private var showingDeleteConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var didLoad = false
    @State private var loadedDraft: [AnyHashable] = []

    /// Gallons and price as loaded from the saved log. Until the person
    /// changes one of them, the total isn't recalculated, so a saved total
    /// that includes a discount or rounding is kept as-is.
    @State private var loadedGallonsText = ""
    @State private var loadedPriceText = ""

    private var isEditing: Bool { log != nil }
    private var gallonsValue: Double { Double(gallonsText) ?? 0 }
    private var priceValue: Double { Double(priceText) ?? 0 }

    private var enteredMileage: Int? {
        DigitsField.value(of: mileageText).map { convertToMiles($0, from: distanceUnit) }
    }

    /// DEF only applies to diesel. If the grade is changed away from diesel,
    /// the hidden toggle is ignored rather than saved.
    private var effectiveDefAdded: Bool { fuelGrade == .diesel && defAdded }

    private var validationIssue: String? {
        if enteredMileage == nil {
            return "Enter the odometer reading to save."
        }
        if gallonsValue <= 0 {
            return "Enter the gallons pumped."
        }
        if (Double(totalCostText) ?? 0) <= 0 && priceValue <= 0 {
            return "Enter the price per gallon or the total cost."
        }
        if isLoadingPhoto {
            return "Waiting for the receipt photo to finish loading…"
        }
        return nil
    }

    private var draft: [AnyHashable] {
        formSnapshot(
            date, DigitsField.value(of: mileageText), fuelGrade,
            Double(gallonsText), Double(priceText), Double(totalCostText), isFullTank,
            stationName, paymentMethod, effectiveDefAdded, Double(defAmountText),
            notes, receiptPhotoData
        )
    }

    private var hasChanges: Bool { didLoad && draft != loadedDraft }

    var body: some View {
        NavigationStack {
            Form {
                if didLoad, let validationIssue {
                    Section { FormIssueRow(message: validationIssue) }
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DigitsField(
                        label: "Odometer (\(distanceUnit.rawValue))",
                        placeholder: "Odometer",
                        text: $mileageText
                    )
                    Picker("Fuel Grade", selection: $fuelGrade) {
                        ForEach(FuelGrade.allCases) { grade in
                            Text(grade.rawValue).tag(grade)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Gallons")
                        Spacer()
                        AutoDecimalField(title: "Gallons", text: $gallonsText, decimalPlaces: 3, prefix: nil)
                            .onChange(of: gallonsText) { _, _ in updateSuggestedTotal() }
                    }
                    HStack {
                        Text("Price / Gallon")
                        Spacer()
                        AutoDecimalField(title: "Price", text: $priceText, decimalPlaces: 3)
                            .onChange(of: priceText) { _, _ in updateSuggestedTotal() }
                    }
                    HStack {
                        Text("Total Cost")
                        Spacer()
                        AutoDecimalField(title: "Total", text: $totalCostText)
                            .onChange(of: totalCostText) { _, _ in recalculateFuelMath(changed: .total) }
                    }
                    Toggle("Filled to Full Tank", isOn: $isFullTank)
                } footer: {
                    Text("Enter any two of Gallons, Price/Gallon, and Total Cost, and the third fills in automatically. Changing gallons or price recalculates the total, so enter any discount in Total Cost last.")
                }

                Section {
                    AutocompleteField(title: "Station Name / Location", text: $stationName, history: stationNameHistory)
                    Picker("Payment Method", selection: $paymentMethod) {
                        ForEach(FuelPaymentMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                }

                if fuelGrade == .diesel {
                    Section {
                        Toggle("DEF Added", isOn: $defAdded)
                        if defAdded {
                            HStack {
                                Text("DEF Amount")
                                Spacer()
                                AutoDecimalField(title: "Gallons", text: $defAmountText, decimalPlaces: 3, prefix: nil)
                                Text("gal")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("Diesel Exhaust Fluid")
                    }
                }

                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                    ReceiptPhotoField(photoData: $receiptPhotoData, isLoading: $isLoadingPhoto)
                }

                if isEditing {
                    Section {
                        Button("Delete Fuel Log", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                        .deleteConfirmation("Delete this fuel log?", isPresented: $showingDeleteConfirm) {
                            deleteAndDismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Fuel" : "Log Fuel")
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { showingDiscardConfirm = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(validationIssue != nil)
                }
            }
            .onAppear(perform: loadExistingValues)
            .discardChangesGuard(hasChanges: hasChanges, isConfirming: $showingDiscardConfirm) { dismiss() }
            .alert(validationTitle, isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    /// Auto-fills Total Cost from Gallons × Price whenever either changes.
    /// The person can still type over it afterward for a discount/tax/rounding.
    private func updateSuggestedTotal() {
        recalculateFuelMath(changed: .gallonsOrPrice)
    }

    /// Gallons, Price/Gallon, and Total Cost are all derivable from each
    /// other. This fills in whichever one is missing. The default flow is
    /// Gallons × Price → Total, but if Gallons hasn't been entered yet and
    /// both Price and Total are known (e.g. reading straight off a receipt),
    /// Gallons gets worked out instead.
    private enum FuelMathSource { case gallonsOrPrice, total }

    private func recalculateFuelMath(changed: FuelMathSource) {
        // Loading an existing log sets gallons and price, which triggers
        // this through onChange. Skip until the person actually changes one,
        // so the saved total isn't replaced just by opening the log.
        if isEditing, gallonsText == loadedGallonsText, priceText == loadedPriceText {
            return
        }
        switch changed {
        case .gallonsOrPrice:
            if gallonsText.isEmpty, priceValue > 0, let total = Double(totalCostText), total > 0 {
                gallonsText = String(format: "%.3f", total / priceValue)
            } else if !gallonsText.isEmpty, priceValue > 0 {
                let suggested = gallonsValue * priceValue
                totalCostText = suggested == 0 ? "" : String(format: "%.2f", suggested)
            }
        case .total:
            if gallonsText.isEmpty, priceValue > 0, let total = Double(totalCostText), total > 0 {
                gallonsText = String(format: "%.3f", total / priceValue)
            }
        }
    }

    private func loadExistingValues() {
        guard !didLoad else { return }
        defer {
            loadedDraft = draft
            didLoad = true
        }
        guard let log else { return }
        date = log.date
        mileageText = log.mileage == 0 ? "" : String(convertFromMiles(log.mileage, to: distanceUnit))
        fuelGrade = log.fuelGrade
        gallonsText = log.gallons == 0 ? "" : String(log.gallons)
        priceText = log.pricePerGallon == 0 ? "" : String(log.pricePerGallon)
        totalCostText = log.totalCost == 0 ? "" : String(format: "%.2f", log.totalCost)
        loadedGallonsText = gallonsText
        loadedPriceText = priceText
        isFullTank = log.isFullTank
        stationName = log.stationName
        paymentMethod = log.paymentMethod
        defAdded = log.defAdded
        defAmountText = log.defAmount == 0 ? "" : String(log.defAmount)
        notes = log.notes
        receiptPhotoData = log.receiptPhotoData
    }

    private func showProblem(_ problem: EntryProblem) {
        validationTitle = problem.title
        validationMessage = problem.message
        showingValidationAlert = true
    }

    private func save() {
        guard validationIssue == nil, let mileage = enteredMileage else { return }
        let enteredTotal = Double(totalCostText) ?? 0
        let totalCost = enteredTotal > 0 ? enteredTotal : gallonsValue * priceValue
        let defAdded = effectiveDefAdded
        let defAmount = defAdded ? (Double(defAmountText) ?? 0) : 0

        if let problem = EntryValidation.dateProblem(date, vehicle: vehicle)
            ?? EntryValidation.mileageProblem(date: date, mileage: mileage, vehicle: vehicle, excludingFuelLog: log) {
            showProblem(problem)
            return
        }

        if let log {
            log.date = date
            log.mileage = mileage
            log.fuelGrade = fuelGrade
            log.gallons = gallonsValue
            log.pricePerGallon = priceValue
            log.totalCost = totalCost
            log.isFullTank = isFullTank
            log.stationName = stationName.trimmed
            log.paymentMethod = paymentMethod
            log.defAdded = defAdded
            log.defAmount = defAmount
            log.notes = notes
            log.receiptPhotoData = receiptPhotoData
        } else {
            let newLog = FuelLog(
                date: date,
                mileage: mileage,
                gallons: gallonsValue,
                pricePerGallon: priceValue,
                isFullTank: isFullTank,
                receiptPhotoData: receiptPhotoData,
                totalCost: totalCost,
                fuelGrade: fuelGrade,
                stationName: stationName.trimmed,
                paymentMethod: paymentMethod,
                defAdded: defAdded,
                defAmount: defAmount,
                notes: notes
            )
            newLog.vehicle = vehicle
            context.insert(newLog)
        }

        if mileage > vehicle.currentMileage {
            vehicle.currentMileage = mileage
        }
        Haptics.success()
        dismiss()
    }

    private func deleteAndDismiss() {
        if let log {
            context.delete(log)
        }
        Haptics.delete()
        dismiss()
    }
}
