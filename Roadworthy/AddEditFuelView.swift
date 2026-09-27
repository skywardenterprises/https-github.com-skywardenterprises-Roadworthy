import SwiftUI
import SwiftData

struct AddEditFuelView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles

    // Every fuel log across every vehicle, most recent first — used to
    // build the Station Name autocomplete suggestions. The same gas
    // station serves whichever car you're driving, so this isn't scoped
    // to just the current vehicle.
    //
    // Limited to the 200 most recent fill-ups and to the two fields the
    // suggestions need, instead of fetching every fuel log in the app.
    @Query(Self.stationHistoryDescriptor) private var allFuelLogs: [FuelLog]

    private static var stationHistoryDescriptor: FetchDescriptor<FuelLog> {
        var descriptor = FetchDescriptor<FuelLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.propertiesToFetch = [\.stationName, \.date]
        descriptor.fetchLimit = 200
        return descriptor
    }

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
    @State private var saveError: String?
    @State private var loadedDraft: [AnyHashable] = []

    /// Gallons and price as loaded from the saved log. Until the person
    /// changes one of them, the total isn't recalculated, so a saved total
    /// that includes a discount or rounding is kept as-is.
    @State private var loadedGallonsText = ""
    @State private var loadedPriceText = ""

    /// Which of Gallons, Price/Gallon, and Total Cost the form is currently
    /// calculating from the other two, and the exact text it last wrote
    /// there. Typing into that field makes it the person's own value again.
    @State private var calculatedField: FuelField?
    @State private var calculatedText = ""

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
                            .onChange(of: gallonsText) { _, _ in fuelFieldChanged(.gallons) }
                    }
                    HStack {
                        Text("Price / Gallon")
                        Spacer()
                        AutoDecimalField(title: "Price", text: $priceText, decimalPlaces: 3)
                            .onChange(of: priceText) { _, _ in fuelFieldChanged(.price) }
                    }
                    HStack {
                        Text("Total Cost")
                        if isTotalLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        Spacer()
                        AutoDecimalField(title: "Total", text: $totalCostText)
                            .onChange(of: totalCostText) { _, _ in fuelFieldChanged(.total) }
                            // Calculated from Gallons × Price, so it can't be
                            // typed over. Clearing Gallons or Price unlocks it.
                            .disabled(isTotalLocked)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(isTotalLocked ? "Calculated from gallons and price. Clear either one to enter a total yourself." : "")
                    Toggle("Filled to Full Tank", isOn: $isFullTank)
                } footer: {
                    Text("Enter any two of Gallons, Price/Gallon, and Total Cost, and the third fills in automatically. When Total Cost is calculated it's locked; to record a discount, enter Gallons and the total you paid, and Price/Gallon is calculated instead.")
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
            .saveErrorAlert($saveError)
            .discardChangesGuard(hasChanges: hasChanges, isConfirming: $showingDiscardConfirm) { dismiss() }
            .alert(validationTitle, isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    // MARK: - Gallons × Price = Total

    private enum FuelField: CaseIterable { case gallons, price, total }

    private func text(_ field: FuelField) -> String {
        switch field {
        case .gallons: return gallonsText
        case .price: return priceText
        case .total: return totalCostText
        }
    }

    private func setText(_ field: FuelField, _ value: String) {
        switch field {
        case .gallons: gallonsText = value
        case .price: priceText = value
        case .total: totalCostText = value
        }
    }

    /// True while Total Cost is being calculated from Gallons × Price. The
    /// field is read-only then; clearing Gallons or Price unlocks it.
    private var isTotalLocked: Bool { calculatedField == .total }

    /// A field's value, or nil if it's blank or zero.
    private func amount(_ field: FuelField) -> Double? {
        guard let value = Double(text(field)), value > 0, value.isFinite else { return nil }
        return value
    }

    /// Runs whenever any of the three fields changes. Any two filled in
    /// calculate the third, in any order:
    /// - Gallons + Price → Total
    /// - Gallons + Total → Price
    /// - Price + Total → Gallons
    /// Once a field is being calculated, it keeps updating as the other two
    /// change (including digit by digit as they're typed). Typing into the
    /// calculated field makes it the person's own value.
    private func fuelFieldChanged(_ field: FuelField) {
        // Loading an existing log sets all three fields, which fires this.
        // Skip until the person actually changes gallons or price, so the
        // saved values aren't recalculated just by opening the log.
        if isEditing, gallonsText == loadedGallonsText, priceText == loadedPriceText {
            return
        }

        // This form's own write coming back through onChange: nothing to do.
        if field == calculatedField, text(field) == calculatedText {
            return
        }
        // The person typed over the calculated field: it's theirs now.
        if field == calculatedField {
            calculatedField = nil
        }

        let target: FuelField?
        if let calculatedField {
            target = calculatedField
        } else {
            let emptyOthers = FuelField.allCases.filter { $0 != field && amount($0) == nil }
            if emptyOthers.count == 1 {
                // Two filled, one empty: fill the empty one.
                target = emptyOthers[0]
            } else if emptyOthers.isEmpty && field != .total {
                // All three typed and gallons or price changed: update Total.
                target = .total
            } else {
                // Only one field filled, or Total edited with all three typed
                // (a discount or rounding): leave everything as entered.
                target = nil
            }
        }

        if let target {
            calculate(target)
        }
    }

    private func calculate(_ target: FuelField) {
        let result: Double?
        switch target {
        case .total:
            result = amount(.gallons).flatMap { g in amount(.price).map { g * $0 } }
        case .gallons:
            result = amount(.total).flatMap { t in amount(.price).map { t / $0 } }
        case .price:
            result = amount(.total).flatMap { t in amount(.gallons).map { t / $0 } }
        }

        guard let result, result.isFinite, result > 0 else {
            // One of the other two was cleared. A calculated value has
            // nothing left to be based on, so clear it too; a typed value is
            // never cleared.
            if calculatedField == target {
                calculatedField = nil
                calculatedText = ""
                setText(target, "")
            }
            return
        }

        // Same precision the fields themselves use.
        let formatted = String(format: target == .total ? "%.2f" : "%.3f", result)
        calculatedField = target
        calculatedText = formatted
        if text(target) != formatted {
            setText(target, formatted)
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
        let previousMileage = log?.mileage
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

        // Editing a fill-up can change the MPG stretches at both its old and
        // new odometer reading, so dismissed warnings there are re-evaluated.
        MPGCalculator.resetIgnoredWarnings(
            affectedBy: [previousMileage, mileage].compactMap { $0 },
            in: vehicle.fuelLogs
        )

        if mileage > vehicle.currentMileage {
            vehicle.currentMileage = mileage
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.success()
        dismiss()
    }

    private func deleteAndDismiss() {
        if let log {
            MPGCalculator.resetIgnoredWarnings(affectedBy: [log.mileage], in: vehicle.fuelLogs)
            context.delete(log)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
        dismiss()
    }
}
