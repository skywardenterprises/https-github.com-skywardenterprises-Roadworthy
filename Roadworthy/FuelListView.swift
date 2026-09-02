import SwiftUI
import SwiftData

struct FuelListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var logToEdit: FuelLog?

    private var sortedLogs: [FuelLog] {
        vehicle.fuelLogs.sorted { $0.date > $1.date }
    }

    // Simple average MPG: (last mileage - first mileage) / total gallons, for full-tank fill-ups.
    private var averageMPG: Double? {
        let fullTankLogs = vehicle.fuelLogs
            .filter { $0.isFullTank }
            .sorted { $0.mileage < $1.mileage }
        guard fullTankLogs.count >= 2,
              let first = fullTankLogs.first,
              let last = fullTankLogs.last,
              last.mileage > first.mileage else { return nil }

        let totalMiles = Double(last.mileage - first.mileage)
        let totalGallons = fullTankLogs.dropFirst().reduce(0) { $0 + $1.gallons }
        guard totalGallons > 0 else { return nil }
        return totalMiles / totalGallons
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
                    Section {
                        ForEach(sortedLogs) { log in
                            Button {
                                logToEdit = log
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("\(log.gallons.formatted(.number.precision(.fractionLength(1)))) gal")
                                            .font(.headline)
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
                                        Text("\(log.mileage.formatted()) mi")
                                        Text("•")
                                        Text("\(log.pricePerGallon, format: .currency(code: "USD"))/gal")
                                        if !log.isFullTank {
                                            Text("• partial")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
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

    // If editing an existing log, pass it in. Nil means "creating new".
    var log: FuelLog?

    @State private var date = Date.now
    @State private var mileageText = ""
    @State private var gallonsText = ""
    @State private var priceText = ""
    @State private var isFullTank = true
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
                DatePicker("Date", selection: $date, displayedComponents: .date)
                HStack {
                    Text("Mileage")
                    Spacer()
                    TextField("Mileage", text: $mileageText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Gallons")
                    Spacer()
                    TextField("Gallons", text: $gallonsText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Price / Gallon")
                    Spacer()
                    TextField("Price", text: $priceText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Filled to Full Tank", isOn: $isFullTank)
                ReceiptPhotoField(photoData: $receiptPhotoData)

                if gallonsValue > 0 {
                    LabeledContent("Total") {
                        Text(gallonsValue * priceValue, format: .currency(code: "USD"))
                    }
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

    private func loadExistingValues() {
        guard let log else { return }
        date = log.date
        mileageText = log.mileage == 0 ? "" : String(log.mileage)
        gallonsText = log.gallons == 0 ? "" : String(log.gallons)
        priceText = log.pricePerGallon == 0 ? "" : String(log.pricePerGallon)
        isFullTank = log.isFullTank
        receiptPhotoData = log.receiptPhotoData
    }

    private func save() {
        let mileage = Int(mileageText) ?? 0

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
            log.gallons = gallonsValue
            log.pricePerGallon = priceValue
            log.isFullTank = isFullTank
            log.receiptPhotoData = receiptPhotoData
        } else {
            let newLog = FuelLog(
                date: date,
                mileage: mileage,
                gallons: gallonsValue,
                pricePerGallon: priceValue,
                isFullTank: isFullTank,
                receiptPhotoData: receiptPhotoData
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
