import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var tripToEdit: TripLog?

    // The IRS standard mileage rate changes periodically (sometimes mid-year).
    // Stored as a simple device setting so it's easy to update without an app update.
    @AppStorage("businessMileageRate") private var mileageRate: Double = 0.76
    @State private var showingRateEditor = false
    @State private var rateText = ""

    private var sortedTrips: [TripLog] {
        vehicle.trips.sorted { $0.date > $1.date }
    }
    private var totalBusinessMiles: Int {
        sortedTrips.filter { $0.purpose == .business }.reduce(0) { $0 + $1.milesDriven }
    }
    private var estimatedDeduction: Double {
        Double(totalBusinessMiles) * mileageRate
    }

    var body: some View {
        Group {
            if sortedTrips.isEmpty {
                ContentUnavailableView(
                    "No Trips Yet",
                    systemImage: "map.fill",
                    description: Text("Business, personal, or commuting — log a trip here to start tracking your mileage.")
                )
            } else {
                List {
                    Section {
                        HStack {
                            Text("Business Miles")
                            Spacer()
                            Text("\(totalBusinessMiles.formatted()) mi")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Estimated Deduction")
                            Spacer()
                            Text(estimatedDeduction, format: .currency(code: "USD"))
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            rateText = String(format: "%.3f", mileageRate)
                            showingRateEditor = true
                        } label: {
                            HStack {
                                Text("Mileage Rate")
                                Spacer()
                                Text("$" + String(format: "%.3f", mileageRate) + "/mi")
                            }
                        }
                        .foregroundStyle(.primary)
                    }

                    Section("Trips") {
                        ForEach(sortedTrips) { trip in
                            Button {
                                tripToEdit = trip
                            } label: {
                                tripRow(trip)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                        .onDelete(perform: deleteTrips)
                    }
                }
            }
        }
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $tripToEdit) { trip in
            AddEditTripView(vehicle: vehicle, trip: trip)
        }
        .alert("Mileage Rate", isPresented: $showingRateEditor) {
            TextField("Rate per mile", text: $rateText)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let value = Double(rateText) {
                    mileageRate = value
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The IRS standard mileage rate changes periodically — sometimes mid-year. Update this to match the current rate for an accurate deduction estimate.")
        }
    }

    private func tripRow(_ trip: TripLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.purpose.rawValue)
                    .font(.headline)
                Spacer()
                Text("\(trip.milesDriven.formatted()) mi")
                    .foregroundStyle(.secondary)
            }
            Text(trip.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !trip.fromLocation.isEmpty || !trip.toLocation.isEmpty {
                Text("\(trip.fromLocation) → \(trip.toLocation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if trip.purpose == .business && !trip.businessPurposeNote.isEmpty {
                Text(trip.businessPurposeNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedTrips[index])
        }
    }
}

struct AddEditTripView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    // If editing an existing trip, pass it in. Nil means "creating new".
    var trip: TripLog?

    @State private var date = Date.now
    @State private var startMileageText = ""
    @State private var endMileageText = ""
    @State private var purpose: TripPurpose = .business
    @State private var businessPurposeNote = ""
    @State private var fromLocation = ""
    @State private var toLocation = ""

    private var isEditing: Bool { trip != nil }
    private var milesDriven: Int {
        let start = Int(startMileageText) ?? 0
        let end = Int(endMileageText) ?? 0
        return max(0, end - start)
    }
    private var canSave: Bool {
        guard let start = Int(startMileageText), let end = Int(endMileageText), end > start else { return false }
        if purpose == .business && businessPurposeNote.isEmpty { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("Start Mileage")
                        Spacer()
                        TextField("Mileage", text: $startMileageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("End Mileage")
                        Spacer()
                        TextField("Mileage", text: $endMileageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if milesDriven > 0 {
                        LabeledContent("Miles Driven", value: "\(milesDriven.formatted()) mi")
                    }
                }

                Section {
                    Picker("Purpose", selection: $purpose) {
                        ForEach(TripPurpose.allCases) { purpose in
                            Text(purpose.rawValue).tag(purpose)
                        }
                    }
                    .pickerStyle(.segmented)
                    if purpose == .business {
                        TextField("Business Purpose (required)", text: $businessPurposeNote, axis: .vertical)
                    }
                } footer: {
                    if purpose == .business {
                        Text("The IRS requires a documented business purpose for each trip, like \"Client meeting downtown\" or \"Parts pickup.\"")
                    }
                }

                Section("Locations (Optional)") {
                    TextField("From", text: $fromLocation)
                    TextField("To", text: $toLocation)
                }

                if isEditing {
                    Section {
                        Button("Delete Trip", role: .destructive) {
                            deleteAndDismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Trip" : "Log Trip")
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadExistingValues)
        }
    }

    private func loadExistingValues() {
        guard let trip else {
            startMileageText = vehicle.currentMileage == 0 ? "" : String(vehicle.currentMileage)
            return
        }
        date = trip.date
        startMileageText = String(trip.startMileage)
        endMileageText = String(trip.endMileage)
        purpose = trip.purpose
        businessPurposeNote = trip.businessPurposeNote
        fromLocation = trip.fromLocation
        toLocation = trip.toLocation
    }

    private func save() {
        let start = Int(startMileageText) ?? 0
        let end = Int(endMileageText) ?? 0

        if let trip {
            trip.date = date
            trip.startMileage = start
            trip.endMileage = end
            trip.purpose = purpose
            trip.businessPurposeNote = purpose == .business ? businessPurposeNote : ""
            trip.fromLocation = fromLocation
            trip.toLocation = toLocation
        } else {
            let newTrip = TripLog(
                date: date,
                startMileage: start,
                endMileage: end,
                purpose: purpose,
                businessPurposeNote: purpose == .business ? businessPurposeNote : "",
                fromLocation: fromLocation,
                toLocation: toLocation
            )
            newTrip.vehicle = vehicle
            context.insert(newTrip)
        }

        if end > vehicle.currentMileage {
            vehicle.currentMileage = end
        }
        Haptics.success()
        dismiss()
    }

    private func deleteAndDismiss() {
        if let trip {
            context.delete(trip)
        }
        Haptics.delete()
        dismiss()
    }
}
