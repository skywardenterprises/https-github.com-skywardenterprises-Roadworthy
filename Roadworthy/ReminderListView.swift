import SwiftUI
import SwiftData

struct ReminderListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var reminderToEdit: MaintenanceReminder?

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
                    .onDelete(perform: deleteReminders)
                }
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
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
                (
                    Text("Every \(reminder.intervalMiles.formatted()) mi — next at ")
                        .foregroundStyle(.secondary)
                    + Text("\(nextDueMileage.formatted()) mi")
                        .foregroundStyle(mileageColor(reminder))
                )
                .font(.caption)
            }
            if let nextDueDate = reminder.nextDueDate {
                (
                    Text("Every \(reminder.intervalMonths) mo — next on ")
                        .foregroundStyle(.secondary)
                    + Text(nextDueDate.formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(dateColor(reminder))
                )
                .font(.caption)
            }
            if !reminder.notes.isEmpty {
                Text(reminder.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Mileage number: red once past due, orange within 2 weeks / 1,000 miles
    // of being due, otherwise the normal secondary color.
    private func mileageColor(_ reminder: MaintenanceReminder) -> Color {
        if reminder.isDue(currentMileage: vehicle.currentMileage) { return .red }
        if reminder.isDueSoon(currentMileage: vehicle.currentMileage) { return .orange }
        return .secondary
    }

    // Due date: red once past due, otherwise the normal secondary color.
    private func dateColor(_ reminder: MaintenanceReminder) -> Color {
        reminder.isDue(currentMileage: vehicle.currentMileage) ? .red : .secondary
    }

    private func deleteReminders(at offsets: IndexSet) {
        for index in offsets {
            let reminder = sortedReminders[index]
            ReminderNotificationManager.cancel(for: reminder)
            context.delete(reminder)
        }
    }
}

struct AddEditReminderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    // If editing an existing reminder, pass it in. Nil means "creating new".
    var reminder: MaintenanceReminder?

    @State private var type: MaintenanceType = .oilChange
    @State private var title = ""
    @State private var otherTypeDescription = ""
    @State private var notes = ""

    @State private var repeatByMileage = false
    @State private var intervalMilesText = ""

    @State private var repeatByDate = false
    @State private var intervalMonthsText = ""

    @State private var notificationsEnabled = false
    @State private var notifyDaysBefore = 0

    private var isEditing: Bool { reminder != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(MaintenanceType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    if type == .other {
                        TextField("Describe the maintenance type", text: $otherTypeDescription)
                    }
                    TextField("Title (optional)", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                Section("Repeat By Mileage") {
                    Toggle("Repeat Every X Miles", isOn: $repeatByMileage)
                    if repeatByMileage {
                        HStack {
                            Text("Every")
                            Spacer()
                            TextField("Miles", text: $intervalMilesText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("mi")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Repeat By Date") {
                    Toggle("Repeat Every X Months", isOn: $repeatByDate)
                    if repeatByDate {
                        HStack {
                            Text("Every")
                            Spacer()
                            TextField("Months", text: $intervalMonthsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("mo")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if repeatByMileage && repeatByDate {
                    Section {
                        Text("Whichever happens first — the mileage or the date — is what triggers this reminder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notifications") {
                    if repeatByDate {
                        Toggle("Notify Me", isOn: $notificationsEnabled)
                        if notificationsEnabled {
                            Stepper(
                                "Remind me \(notifyDaysBefore) day\(notifyDaysBefore == 1 ? "" : "s") before",
                                value: $notifyDaysBefore,
                                in: 0...30
                            )
                        }
                    } else {
                        Text("Turn on \"Repeat Every X Months\" above to enable notifications — mileage-only reminders can't be scheduled in advance, since there's no way to predict when a certain mileage will be reached.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if isEditing {
                    Section {
                        Button("Mark as Done (Reschedule)") {
                            markDone()
                        }
                        Button("Delete Reminder", role: .destructive) {
                            deleteAndDismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Reminder" : "New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!repeatByMileage && !repeatByDate)
                }
            }
            .onAppear(perform: loadExistingValues)
        }
    }

    private func loadExistingValues() {
        guard let reminder else { return }
        type = reminder.type
        title = reminder.title
        notes = reminder.notes
        repeatByMileage = reminder.repeatByMileage
        intervalMilesText = reminder.intervalMiles == 0 ? "" : String(reminder.intervalMiles)
        repeatByDate = reminder.repeatByDate
        intervalMonthsText = reminder.intervalMonths == 0 ? "" : String(reminder.intervalMonths)
        notificationsEnabled = reminder.notificationsEnabled
        notifyDaysBefore = reminder.notifyDaysBefore
        if type == .other && title != MaintenanceType.other.rawValue {
            otherTypeDescription = title
        }
    }

    private func save() {
        let intervalMiles = Int(intervalMilesText) ?? 0
        let intervalMonths = Int(intervalMonthsText) ?? 0

        var finalTitle = title
        if finalTitle.isEmpty && type == .other && !otherTypeDescription.isEmpty {
            finalTitle = otherTypeDescription
        }
        if finalTitle.isEmpty {
            finalTitle = type.rawValue
        }

        let savedReminder: MaintenanceReminder
        if let reminder {
            reminder.type = type
            reminder.title = finalTitle
            reminder.notes = notes
            reminder.repeatByMileage = repeatByMileage
            reminder.intervalMiles = intervalMiles
            reminder.repeatByDate = repeatByDate
            reminder.intervalMonths = intervalMonths
            reminder.notificationsEnabled = notificationsEnabled
            reminder.notifyDaysBefore = notifyDaysBefore
            savedReminder = reminder
        } else {
            let newReminder = MaintenanceReminder(
                title: finalTitle,
                type: type,
                notes: notes,
                repeatByMileage: repeatByMileage,
                intervalMiles: intervalMiles,
                repeatByDate: repeatByDate,
                intervalMonths: intervalMonths,
                baselineMileage: vehicle.currentMileage,
                baselineDate: .now,
                notificationsEnabled: notificationsEnabled,
                notifyDaysBefore: notifyDaysBefore
            )
            newReminder.vehicle = vehicle
            context.insert(newReminder)
            savedReminder = newReminder
        }

        if notificationsEnabled {
            ReminderNotificationManager.requestAuthorizationIfNeeded()
        }
        ReminderNotificationManager.schedule(for: savedReminder, vehicleName: vehicle.displayName)
        Haptics.success()
        dismiss()
    }

    /// Resets the reminder's starting point to right now, so the next
    /// occurrence is calculated from today's mileage and date.
    private func markDone() {
        guard let reminder else { return }
        reminder.baselineMileage = vehicle.currentMileage
        reminder.baselineDate = .now
        ReminderNotificationManager.schedule(for: reminder, vehicleName: vehicle.displayName)
        Haptics.success()
        dismiss()
    }

    private func deleteAndDismiss() {
        if let reminder {
            ReminderNotificationManager.cancel(for: reminder)
            context.delete(reminder)
        }
        Haptics.delete()
        dismiss()
    }
}
