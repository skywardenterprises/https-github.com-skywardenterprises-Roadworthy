import SwiftUI
import SwiftData

struct FuelListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var showingAdd = false

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
                    "No Fuel Logged",
                    systemImage: "fuelpump",
                    description: Text("Tap + to log a fill-up.")
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
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(log.gallons.formatted(.number.precision(.fractionLength(1)))) gal")
                                        .font(.headline)
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
                        }
                        .onDelete(perform: deleteLogs)
                    }
                }
            }
        }
        .navigationTitle("Fuel")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddFuelView(vehicle: vehicle)
        }
    }

    private func deleteLogs(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedLogs[index])
        }
    }
}

struct AddFuelView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    @State private var date = Date.now
    @State private var mileage = 0
    @State private var gallons = 0.0
    @State private var pricePerGallon = 0.0
    @State private var isFullTank = true

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                HStack {
                    Text("Mileage")
                    Spacer()
                    TextField("Mileage", value: $mileage, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Gallons")
                    Spacer()
                    TextField("Gallons", value: $gallons, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Price / Gallon")
                    Spacer()
                    TextField("Price", value: $pricePerGallon, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Filled to Full Tank", isOn: $isFullTank)

                if gallons > 0 {
                    LabeledContent("Total") {
                        Text(gallons * pricePerGallon, format: .currency(code: "USD"))
                    }
                }
            }
            .navigationTitle("Log Fuel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let log = FuelLog(
            date: date,
            mileage: mileage,
            gallons: gallons,
            pricePerGallon: pricePerGallon,
            isFullTank: isFullTank
        )
        log.vehicle = vehicle
        context.insert(log)
        if mileage > vehicle.currentMileage {
            vehicle.currentMileage = mileage
        }
        dismiss()
    }
}
