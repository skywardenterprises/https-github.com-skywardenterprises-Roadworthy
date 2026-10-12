import SwiftUI
import SwiftData

/// Shown when a vehicle's odometer hasn't been touched for 30 days. Offers
/// to log the missing maintenance or fuel, or to record the current reading
/// by hand so mileage-based reminders stay accurate.
struct OdometerCheckInView: View {
    static let gapDays = 30
    private static let snoozeDays = 7

    let vehicle: Vehicle
    let onLogMaintenance: () -> Void
    let onLogFuel: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles

    @State private var readingText = ""
    @State private var saveError: String?
    @State private var showError = false

    private var daysSince: Int {
        guard let last = vehicle.lastOdometerActivityDate else { return Self.gapDays }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: .now)
        ).day ?? Self.gapDays
    }

    private var enteredMiles: Int? {
        DigitsField.value(of: readingText).map { convertToMiles($0, from: distanceUnit) }
    }

    private var issue: String? {
        guard let miles = enteredMiles else { return nil }
        if miles <= 0 { return L("Enter the odometer reading shown on the dash.") }
        if miles < vehicle.currentMileage {
            return L("That's lower than the last reading (%@). If that reading was a mistake, correct it from Edit Vehicle.", formattedDistance(vehicle.currentMileage, unit: distanceUnit))
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("It's been \(daysSince) days since the odometer was last updated for \(vehicle.displayName). Last known reading: \(formattedDistance(vehicle.currentMileage, unit: distanceUnit)).")
                        .font(.subheadline)
                }

                Section {
                    Button { onLogMaintenance() } label: {
                        Label("I had maintenance done", systemImage: "wrench.and.screwdriver.fill")
                    }
                    Button { onLogFuel() } label: {
                        Label("I filled up", systemImage: "fuelpump.fill")
                    }
                } header: {
                    Text("Has anything happened since?")
                }

                Section {
                    DigitsField(
                        label: "Odometer (\(distanceUnit.rawValue))",
                        placeholder: "Current reading",
                        text: $readingText
                    )
                    if let issue {
                        Text(issue).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Save Odometer Reading") { saveReading() }
                        .disabled(enteredMiles == nil || issue != nil)
                } header: {
                    Text("Nothing to log? Enter the current odometer")
                } footer: {
                    Text("Reminders that are due by odometer use this reading.")
                }

                Section {
                    Button("Remind Me Later", role: .cancel) { snooze() }
                }
            }
            .navigationTitle("Odometer Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn't Save", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
        .interactiveDismissDisabled()
    }

    private func saveReading() {
        guard let miles = enteredMiles, issue == nil else { return }
        vehicle.currentMileage = miles
        vehicle.odometerUpdatedDate = .now
        if let message = context.saveReportingErrors() {
            saveError = message
            showError = true
            return
        }
        UserDefaults.standard.removeObject(forKey: SettingKey.odometerSnooze(vehicle.stableID))
        Haptics.success()
        dismiss()
    }

    private func snooze() {
        let until = Calendar.current.date(byAdding: .day, value: Self.snoozeDays, to: .now) ?? .now
        UserDefaults.standard.set(until, forKey: SettingKey.odometerSnooze(vehicle.stableID))
        dismiss()
    }
}
