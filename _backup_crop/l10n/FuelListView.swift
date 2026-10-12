import SwiftUI
import SwiftData

struct FuelListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles
    @State private var logToEdit: FuelLog?
    @State private var pendingDeletion: [FuelLog] = []
    @State private var saveError: String?

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
    private var logsMissingOdometer: [FuelLog] {
        MPGCalculator.logsMissingOdometer(for: vehicle.fuelLogs)
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
                    if !flaggedIntervals.isEmpty || !logsMissingOdometer.isEmpty {
                        Section {
                            ForEach(logsMissingOdometer) { log in
                                Button {
                                    logToEdit = log
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label("No odometer reading", systemImage: "exclamationmark.triangle.fill")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                        Text("Fill-up on \(log.date.formatted(date: .abbreviated, time: .omitted)). Add the reading so it can count toward MPG.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
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
                            Text("These fill-ups need a look, usually because of a typo, a missed fill-up, or a fill-up marked full/partial incorrectly. Tap one to fix it, or swipe an MPG warning to ignore it — they're excluded from Average MPG either way.")
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
        .saveErrorAlert($saveError)
        .sheet(item: $logToEdit) { log in
            AddEditFuelView(vehicle: vehicle, log: log)
        }
    }

    private func flaggedIntervalRow(_ interval: MPGInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                // An MPG of 0 means it couldn't be calculated at all, so
                // "0.0 MPG calculated" would be misleading.
                Text(interval.mpg > 0
                     ? "\(interval.mpg.formatted(.number.precision(.fractionLength(1)))) MPG calculated"
                     : "MPG couldn't be calculated")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            Text("\(interval.startLog.date.formatted(date: .abbreviated, time: .omitted)) → \(interval.endLog.date.formatted(date: .abbreviated, time: .omitted))  •  \(interval.milesDriven.formatted()) mi on \(interval.gallonsUsed.formatted(.number.precision(.fractionLength(1)))) gal")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let reason = interval.issueDescription {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                Text(log.totalCost, format: .currency(code: AppCurrency.code))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(log.date.formatted(date: .abbreviated, time: .omitted))
                Text("•")
                Text(formattedDistance(log.mileage, unit: distanceUnit))
                Text("•")
                Text("\(log.pricePerGallon, format: .currency(code: AppCurrency.code))/gal")
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
        // Deleting a fill-up changes the MPG stretches around it, so any
        // "ignore" on those stretches is cleared and re-evaluated.
        MPGCalculator.resetIgnoredWarnings(affectedBy: logs.map(\.mileage), in: vehicle.fuelLogs)
        for log in logs {
            context.delete(log)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
    }
}
