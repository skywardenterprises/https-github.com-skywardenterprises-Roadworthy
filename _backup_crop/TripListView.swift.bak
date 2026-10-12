import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles
    @State private var tripToEdit: TripLog?
    @State private var pendingDeletion: [TripLog] = []
    @State private var saveError: String?

    // The IRS standard mileage rate changes periodically (sometimes mid-year).
    // Stored as a simple device setting so it's easy to update without an app update.
    @AppStorage(SettingKey.businessMileageRate) private var mileageRate: Double = SettingDefault.businessMileageRate
    @State private var showingRateEditor = false

    private var sortedTrips: [TripLog] {
        vehicle.trips.sorted { $0.date > $1.date }
    }
    /// Business distance and deduction for the current tax year, matching
    /// Reports and the Business Mileage Log PDF. The IRS rate is per year,
    /// so a total across every year can't be multiplied by one rate.
    private var currentTaxYear: Int { Calendar.current.component(.year, from: .now) }
    private var businessMilesThisYear: Int {
        sortedTrips
            .filter { $0.purpose == .business && Calendar.current.component(.year, from: $0.date) == currentTaxYear }
            .reduce(0) { $0 + $1.milesDriven }
    }
    private var estimatedDeduction: Double {
        Double(businessMilesThisYear) * mileageRate
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
                            Text("\(String(currentTaxYear)) Business \(distanceUnit.displayName)")
                            Spacer()
                            Text(formattedDistance(businessMilesThisYear, unit: distanceUnit))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("\(String(currentTaxYear)) Estimated Deduction")
                            Spacer()
                            Text(estimatedDeduction, format: .currency(code: AppCurrency.code))
                                .foregroundStyle(.secondary)
                        }
                        Button {
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
                        .onDelete { offsets in pendingDeletion = offsets.map { sortedTrips[$0] } }
                    }
                }
            }
        }
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.inline)
        .confirmDeletion(of: $pendingDeletion, noun: "trip") { deleteTrips($0) }
        .saveErrorAlert($saveError)
        .sheet(item: $tripToEdit) { trip in
            AddEditTripView(vehicle: vehicle, trip: trip)
        }
        .sheet(isPresented: $showingRateEditor) {
            MileageRateEditor(rate: $mileageRate)
        }
    }

    private func tripRow(_ trip: TripLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.purpose.rawValue)
                    .font(.headline)
                Spacer()
                Text(formattedDistance(trip.milesDriven, unit: distanceUnit))
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

    private func deleteTrips(_ trips: [TripLog]) {
        for trip in trips {
            context.delete(trip)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
    }
}

/// Edits the IRS mileage rate. A sheet rather than an alert so it can
/// explain what's wrong with an entry. Accepts a comma as the decimal point
/// (French and Spanish keyboards type "0,70", which `Double` can't read, so
/// the rate used to silently not change), and only allows $0.01–$5.00 per
/// mile, which catches values typed in cents like "70".
struct MileageRateEditor: View {
    @Binding var rate: Double
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    static let allowedRange = 0.01...5.0

    private var parsedRate: Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return value
    }

    private var validationIssue: String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "Enter the rate in dollars per mile." }
        guard let value = parsedRate else { return "Enter the rate as a number, like 0.70." }
        guard Self.allowedRange.contains(value) else {
            return "Enter a rate between $0.01 and $5.00 per mile. For 70 cents, enter 0.70."
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$")
                        TextField("0.700", text: $text)
                            .keyboardType(.decimalPad)
                        Text("per mile").foregroundStyle(.secondary)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let validationIssue {
                            Text(validationIssue).foregroundStyle(.orange)
                        }
                        Text("The IRS standard mileage rate changes periodically — sometimes mid-year. Update this to match the current rate for an accurate deduction estimate.")
                    }
                }
            }
            .navigationTitle("Mileage Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = parsedRate, validationIssue == nil {
                            rate = value
                            Haptics.success()
                            dismiss()
                        }
                    }
                    .disabled(validationIssue != nil)
                }
            }
            .onAppear { text = String(format: "%.3f", rate) }
        }
        .presentationDetents([.medium])
    }
}
