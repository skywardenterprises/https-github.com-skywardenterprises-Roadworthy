import SwiftUI
import SwiftData
import UIKit

struct ReminderListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles
    @State private var reminderToEdit: MaintenanceReminder?
    @State private var pendingDeletion: [MaintenanceReminder] = []
    @State private var saveError: String?

    // Reminders with the least mileage remaining show first (this also
    // naturally surfaces overdue reminders first, since overdue mileage is
    // negative). Reminders with no mileage component sort after those, by
    // days remaining.
    private var sortedReminders: [MaintenanceReminder] {
        vehicle.reminders.sorted {
            $0.sortKey(currentMileage: vehicle.currentMileage) < $1.sortKey(currentMileage: vehicle.currentMileage)
        }
    }

    var body: some View {
        Group {
            if sortedReminders.isEmpty {
                ContentUnavailableView(
                    "No Reminders Yet",
                    systemImage: "bell.fill",
                    description: Text("Never miss another oil change or inspection — set a recurring reminder here.")
                )
            } else {
                List {
                    ForEach(sortedReminders) { reminder in
                        Button {
                            reminderToEdit = reminder
                        } label: {
                            reminderRow(reminder)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in pendingDeletion = offsets.map { sortedReminders[$0] } }
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .confirmDeletion(of: $pendingDeletion, noun: "reminder") { deleteReminders($0) }
        .saveErrorAlert($saveError)
        .sheet(item: $reminderToEdit) { reminder in
            AddEditReminderView(vehicle: vehicle, reminder: reminder)
        }
    }

    private func reminderRow(_ reminder: MaintenanceReminder) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(reminder.title).font(.headline)
                if reminder.notificationsEnabled {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ReminderStatusBadge(status: reminder.status(currentMileage: vehicle.currentMileage))
            }
            if let nextDueMileage = reminder.nextDueMileage {
                Text("Every \(convertFromMiles(reminder.intervalMiles, to: distanceUnit).formatted()) \(distanceUnit.rawValue) — next at \(Text(formattedDistance(nextDueMileage, unit: distanceUnit)).foregroundStyle(reminder.mileageTint(currentMileage: vehicle.currentMileage)))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if let nextDueDate = reminder.nextDueDate {
                Text("Every \(reminder.intervalMonths) mo — next on \(Text(nextDueDate.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(reminder.dateTint(currentMileage: vehicle.currentMileage)))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if !reminder.notes.isEmpty {
                Text(reminder.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteReminders(_ reminders: [MaintenanceReminder]) {
        for reminder in reminders {
            ReminderNotificationManager.cancel(for: reminder)
            context.delete(reminder)
        }
        if let message = context.saveReportingErrors() {
            // The deletes were rolled back, so their notifications go back too.
            for reminder in reminders {
                ReminderNotificationManager.schedule(for: reminder, vehicleName: vehicle.displayName)
            }
            saveError = message
            return
        }
        Haptics.delete()
    }
}
