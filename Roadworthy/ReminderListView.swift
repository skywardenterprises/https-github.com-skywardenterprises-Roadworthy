import SwiftUI
import SwiftData

struct ReminderListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @Binding var showingAdd: Bool
    @State private var reminderToEdit: MaintenanceReminder?

    // Reminders that are already due show first, then soonest-due next.
    private var sortedReminders: [MaintenanceReminder] {
        vehicle.reminders.sorted { lhs, rhs in
            let lhsDue = lhs.isDue(currentMileage: vehicle.currentMileage)
            let rhsDue = rhs.isDue(currentMileage: vehicle.currentMileage)
            if lhsDue != rhsDue { return lhsDue && !rhsDue }
            return (lhs.nextDueDate ?? .distantFuture) < (rhs.nextDueDate ?? .distantFuture)
        }
    }

    var body: some View {
        Group {
            if sortedReminders.isEmpty {
                ContentUnavailableView(
                    "No Reminders Set",
                    systemImage: "bell",
                    description: Text("Tap the + button below to set up a recurring reminder.")
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
        .sheet(isPresented: $showingAdd) {
            AddEditReminderView(vehicle: vehicle, reminder: nil)
        }
        .sheet(item: $reminderToEdit) { reminder in
            AddEditReminderView(vehicle: vehicle, reminder: reminder)
        }
    }

    private func reminderRow(_ reminder: MaintenanceReminder) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(reminder.title).font(.headline)
                Spacer()
                if reminder.isDue(currentMileage: vehicle.currentMileage) {
                    Text("Due")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.red))
                }
            }
            if let nextDueMileage = reminder.nextDueMileage {
                Text("Every \(reminder.intervalMiles.formatted()) mi — next at \(nextDueMileage.formatted()) mi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let nextDueDate = reminder.nextDueDate {
                Text("Every \(reminder.intervalMonths) mo — next on \(nextDueDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !reminder.notes.isEmpty {
                Text(reminder.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deleteReminders(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedReminders[index])
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

    private var isEditing: Bool { reminder != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(MaintenanceType.allCases) { type in
                            Text(type.rawValue).tag(type)
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

        if let reminder {
            reminder.type = type
            reminder.title = finalTitle
            reminder.notes = notes
            reminder.repeatByMileage = repeatByMileage
            reminder.intervalMiles = intervalMiles
            reminder.repeatByDate = repeatByDate
            reminder.intervalMonths = intervalMonths
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
                baselineDate: .now
            )
            newReminder.vehicle = vehicle
            context.insert(newReminder)
        }
        dismiss()
    }

    /// Resets the reminder's starting point to right now, so the next
    /// occurrence is calculated from today's mileage and date.
    private func markDone() {
        guard let reminder else { return }
        reminder.baselineMileage = vehicle.currentMileage
        reminder.baselineDate = .now
        dismiss()
    }

    private func deleteAndDismiss() {
        if let reminder {
            context.delete(reminder)
        }
        dismiss()
    }
}
