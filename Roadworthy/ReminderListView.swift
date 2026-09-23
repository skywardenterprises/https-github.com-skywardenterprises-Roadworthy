import SwiftUI
import SwiftData
import UIKit

struct ReminderListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .miles
    @State private var reminderToEdit: MaintenanceReminder?
    @State private var pendingDeletion: [MaintenanceReminder] = []

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
                Text("Every \(convertFromMiles(reminder.intervalMiles, to: distanceUnit).formatted()) \(distanceUnit.rawValue) — next at \(Text(formattedDistance(nextDueMileage, unit: distanceUnit)).foregroundStyle(mileageColor(reminder)))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if let nextDueDate = reminder.nextDueDate {
                Text("Every \(reminder.intervalMonths) mo — next on \(Text(nextDueDate.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(dateColor(reminder)))")
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

    private func deleteReminders(_ reminders: [MaintenanceReminder]) {
        for reminder in reminders {
            ReminderNotificationManager.cancel(for: reminder)
            context.delete(reminder)
        }
        Haptics.delete()
    }
}

struct AddEditReminderView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .miles

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
    @State private var showingNotificationPermissionAlert = false

    @State private var showingDeleteConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var didLoad = false
    @State private var loadedDraft: [AnyHashable] = []

    private var isEditing: Bool { reminder != nil }

    private var enteredIntervalMiles: Int {
        convertToMiles(DigitsField.value(of: intervalMilesText) ?? 0, from: distanceUnit)
    }
    private var enteredIntervalMonths: Int { DigitsField.value(of: intervalMonthsText) ?? 0 }

    /// Notifications only apply to date-based repeats. If date repeat is off,
    /// the hidden toggle is ignored rather than saved.
    private var effectiveNotificationsEnabled: Bool { repeatByDate && notificationsEnabled }

    private var validationIssue: String? {
        if !repeatByMileage && !repeatByDate {
            return "Turn on repeat by \(distanceUnit.displayName.lowercased()), by date, or both."
        }
        if repeatByMileage && enteredIntervalMiles <= 0 {
            return "Enter how many \(distanceUnit.displayName.lowercased()) between services."
        }
        if repeatByDate && enteredIntervalMonths <= 0 {
            return "Enter how many months between services."
        }
        return nil
    }

    /// True when the calculated notification date has already passed. The
    /// scheduler skips those, so the person is told instead of expecting a
    /// notification that won't arrive.
    private var notificationDateHasPassed: Bool {
        guard effectiveNotificationsEnabled, enteredIntervalMonths > 0 else { return false }
        let baseline = reminder?.baselineDate ?? .now
        let calendar = Calendar.current
        guard let due = calendar.date(byAdding: .month, value: enteredIntervalMonths, to: baseline),
              let fire = calendar.date(byAdding: .day, value: -notifyDaysBefore, to: due)
        else { return false }
        return fire <= .now
    }

    private var draft: [AnyHashable] {
        formSnapshot(
            type, title, otherTypeDescription, notes,
            repeatByMileage, DigitsField.value(of: intervalMilesText),
            repeatByDate, DigitsField.value(of: intervalMonthsText),
            effectiveNotificationsEnabled, notifyDaysBefore
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

                Section("Repeat By \(distanceUnit.displayName)") {
                    Toggle("Repeat Every X \(distanceUnit.displayName)", isOn: $repeatByMileage)
                    if repeatByMileage {
                        DigitsField(
                            label: "Every",
                            placeholder: distanceUnit.displayName,
                            text: $intervalMilesText,
                            maxDigits: 6,
                            suffix: distanceUnit.rawValue
                        )
                    }
                }

                Section("Repeat By Date") {
                    Toggle("Repeat Every X Months", isOn: $repeatByDate)
                    if repeatByDate {
                        DigitsField(
                            label: "Every",
                            placeholder: "Months",
                            text: $intervalMonthsText,
                            maxDigits: 3,
                            suffix: "mo"
                        )
                    }
                }

                if repeatByMileage && repeatByDate {
                    Section {
                        Text("Whichever happens first — the mileage or the date — is what triggers this reminder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
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
                } header: {
                    Text("Notifications")
                } footer: {
                    if notificationDateHasPassed {
                        Text("This notification date has already passed, so no notification will be scheduled. Mark the reminder as done to start the next interval.")
                    }
                }

                if isEditing {
                    Section {
                        Button("Mark as Done (Reschedule)") {
                            markDone()
                        }
                        // Mark as Done saves right away. With unsaved edits on
                        // screen, those edits would be silently dropped.
                        .disabled(hasChanges)
                        Button("Delete Reminder", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                        .deleteConfirmation("Delete this reminder?", isPresented: $showingDeleteConfirm) {
                            deleteAndDismiss()
                        }
                    } footer: {
                        if hasChanges {
                            Text("Save or discard your changes before marking this done.")
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Reminder" : "New Reminder")
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
            .discardChangesGuard(hasChanges: hasChanges, isConfirming: $showingDiscardConfirm) { dismiss() }
            .onChange(of: notificationsEnabled) { _, newValue in
                guard newValue, didLoad else { return }
                Task { await verifyNotificationPermission() }
            }
            .alert("Notifications Are Off", isPresented: $showingNotificationPermissionAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Roadworthy doesn't have permission to send notifications. Turn them on in Settings, then come back and enable \"Notify Me\" again.")
            }
        }
    }

    private func loadExistingValues() {
        guard !didLoad else { return }
        defer {
            loadedDraft = draft
            didLoad = true
        }
        guard let reminder else { return }
        type = reminder.type
        // Same title handling as maintenance records: a stored type name isn't
        // shown as a typed title, and a custom type's title is its description.
        if reminder.type == .other, reminder.title != MaintenanceType.other.rawValue {
            otherTypeDescription = reminder.title
            title = ""
        } else {
            title = reminder.title == reminder.type.rawValue ? "" : reminder.title
        }
        notes = reminder.notes
        repeatByMileage = reminder.repeatByMileage
        intervalMilesText = reminder.intervalMiles == 0 ? "" : String(convertFromMiles(reminder.intervalMiles, to: distanceUnit))
        repeatByDate = reminder.repeatByDate
        intervalMonthsText = reminder.intervalMonths == 0 ? "" : String(reminder.intervalMonths)
        notificationsEnabled = reminder.notificationsEnabled
        notifyDaysBefore = reminder.notifyDaysBefore
    }

    /// Confirms notifications are actually allowed the moment someone turns
    /// "Notify Me" on. Without this, the toggle can show as enabled while
    /// the system has notifications denied — and the reminder would just
    /// silently never fire with no indication anything's wrong.
    private func verifyNotificationPermission() async {
        let granted = await ReminderNotificationManager.requestAuthorizationIfNeeded()
        if !granted {
            notificationsEnabled = false
            showingNotificationPermissionAlert = true
        }
    }

    private func save() {
        guard validationIssue == nil else { return }
        let intervalMiles = repeatByMileage ? enteredIntervalMiles : 0
        let intervalMonths = repeatByDate ? enteredIntervalMonths : 0
        let notificationsOn = effectiveNotificationsEnabled

        var finalTitle = title.trimmed
        if finalTitle.isEmpty && type == .other {
            finalTitle = otherTypeDescription.trimmed
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
            reminder.notificationsEnabled = notificationsOn
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
                notificationsEnabled: notificationsOn,
                notifyDaysBefore: notifyDaysBefore
            )
            newReminder.vehicle = vehicle
            context.insert(newReminder)
            savedReminder = newReminder
        }

        // Permission is already confirmed by the time "Notify Me" gets
        // turned on (see verifyNotificationPermission), so this just
        // (re)schedules based on the current due date and settings.
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
