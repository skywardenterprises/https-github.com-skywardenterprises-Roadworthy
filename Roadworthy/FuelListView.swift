import SwiftUI
import SwiftData

struct FuelListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .miles
    @State private var logToEdit: FuelLog?

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
                        .onDelete(perform: deleteLogs)
                    }
                }
            }
        }
        .navigationTitle("Fuel")
        .navigationBarTitleDisplayMode(.inline)
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

    private func deleteLogs(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedLogs[index])
        }
    }
}

struct AddEditFuelView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .miles

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
    @State private var showingValidationAlert = false
    @State private var validationTitle = ""
    @State private var validationMessage = ""

    private var isEditing: Bool { log != nil }
    private var gallonsValue: Double { Double(gallonsText) ?? 0 }
    private var priceValue: Double { Double(priceText) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("Odometer (\(distanceUnit.rawValue))")
                        Spacer()
                        TextField("Odometer", text: $mileageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
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
                        TextField("Gallons", text: $gallonsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: gallonsText) { _, _ in updateSuggestedTotal() }
                    }
                    HStack {
                        Text("Price / Gallon")
                        Spacer()
                        TextField("Price", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: priceText) { _, _ in updateSuggestedTotal() }
                    }
                    HStack {
                        Text("Total Cost")
                        Spacer()
                        TextField("Total", text: $totalCostText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("Filled to Full Tank", isOn: $isFullTank)
                } footer: {
                    Text("Total Cost is filled in automatically from Gallons × Price, but you can edit it directly to account for a discount, tax, or rounding.")
                }

                Section {
                    TextField("Station Name / Location", text: $stationName)
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
                                TextField("Gallons", text: $defAmountText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
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
                    ReceiptPhotoField(photoData: $receiptPhotoData)
                }

                if isEditing {
                    Section {
                        Button("Delete Fuel Log", role: .destructive) {
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
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: loadExistingValues)
            .alert(validationTitle, isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    /// Auto-fills Total Cost from Gallons × Price whenever either changes —
    /// the person can still type over it afterward for a discount/tax/rounding.
    private func updateSuggestedTotal() {
        let suggested = gallonsValue * priceValue
        totalCostText = suggested == 0 ? "" : String(format: "%.2f", suggested)
    }

    private func loadExistingValues() {
        guard let log else { return }
        date = log.date
        mileageText = log.mileage == 0 ? "" : String(convertFromMiles(log.mileage, to: distanceUnit))
        fuelGrade = log.fuelGrade
        gallonsText = log.gallons == 0 ? "" : String(log.gallons)
        priceText = log.pricePerGallon == 0 ? "" : String(log.pricePerGallon)
        totalCostText = log.totalCost == 0 ? "" : String(format: "%.2f", log.totalCost)
        isFullTank = log.isFullTank
        stationName = log.stationName
        paymentMethod = log.paymentMethod
        defAdded = log.defAdded
        defAmountText = log.defAmount == 0 ? "" : String(log.defAmount)
        notes = log.notes
        receiptPhotoData = log.receiptPhotoData
    }

    private func save() {
        let mileage = convertToMiles(Int(mileageText) ?? 0, from: distanceUnit)
        let totalCost = Double(totalCostText) ?? (gallonsValue * priceValue)
        let defAmount = defAdded ? (Double(defAmountText) ?? 0) : 0

        if isFutureDate(date) {
            validationTitle = "Date Is In the Future"
            validationMessage = "This entry is dated \(date.formatted(date: .abbreviated, time: .omitted)), which hasn't happened yet. Please choose today's date or an earlier one before saving."
            showingValidationAlert = true
            return
        }

        if isBeforeManufactureYear(date, vehicleYear: vehicle.year) {
            validationTitle = "Date Is Before This Vehicle Existed"
            validationMessage = "This entry is dated \(date.formatted(date: .abbreviated, time: .omitted)), but this vehicle wasn't manufactured until \(vehicle.year). Please choose a date in \(vehicle.year) or later before saving."
            showingValidationAlert = true
            return
        }

        if let conflict = vehicle.mileageConflict(forDate: date, mileage: mileage, excludingFuelLog: log) {
            validationTitle = "Mileage Doesn't Add Up"
            validationMessage = buildMileageConflictMessage(newMileage: mileage, newDate: date, conflict: conflict)
            showingValidationAlert = true
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
            log.stationName = stationName
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
                stationName: stationName,
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
