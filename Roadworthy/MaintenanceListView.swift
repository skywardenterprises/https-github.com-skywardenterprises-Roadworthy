import SwiftUI
import SwiftData

struct MaintenanceListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var recordToEdit: MaintenanceRecord?

    private var sortedRecords: [MaintenanceRecord] {
        vehicle.maintenanceRecords.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sortedRecords.isEmpty {
                ContentUnavailableView(
                    "No Maintenance Logged",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Use the + button to log an oil change, tire rotation, etc.")
                )
            } else {
                List {
                    ForEach(sortedRecords) { record in
                        Button {
                            recordToEdit = record
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.title).font(.headline)
                                    if record.receiptPhotoData != nil {
                                        Image(systemName: "paperclip")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(record.cost, format: .currency(code: "USD"))
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text(record.date.formatted(date: .abbreviated, time: .omitted))
                                    Text("•")
                                    Text("\(record.mileage.formatted()) mi")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                if !record.notes.isEmpty {
                                    Text(record.notes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                    .onDelete(perform: deleteRecords)
                }
            }
        }
        .navigationTitle("Maintenance")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $recordToEdit) { record in
            AddEditMaintenanceView(vehicle: vehicle, record: record)
        }
    }

    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            context.delete(sortedRecords[index])
        }
    }
}

struct AddEditMaintenanceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    // If editing an existing record, pass it in. Nil means "creating new".
    var record: MaintenanceRecord?

    @State private var type: MaintenanceType = .oilChange
    @State private var title = ""
    @State private var otherTypeDescription = ""
    @State private var date = Date.now
    @State private var mileageText = ""
    @State private var costText = ""
    @State private var notes = ""
    @State private var receiptPhotoData: Data?
    @State private var setReminder = false
    @State private var nextDueMileageText = ""
    @State private var nextDueDate = Date.now

    private var isEditing: Bool { record != nil }

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
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    HStack {
                        Text("Mileage")
                        Spacer()
                        TextField("Mileage", text: $mileageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Cost")
                        Spacer()
                        TextField("Cost", text: $costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                    ReceiptPhotoField(photoData: $receiptPhotoData)
                }

                Section {
                    Toggle("Set Next Due Reminder", isOn: $setReminder)
                    if setReminder {
                        DatePicker("Next Due Date", selection: $nextDueDate, displayedComponents: .date)
                        HStack {
                            Text("Next Due Mileage")
                            Spacer()
                            TextField("Mileage", text: $nextDueMileageText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Button("Delete Maintenance Record", role: .destructive) {
                            deleteAndDismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Maintenance" : "Log Maintenance")
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
        }
    }

    private func loadExistingValues() {
        guard let record else { return }
        type = record.type
        title = record.title
        date = record.date
        mileageText = record.mileage == 0 ? "" : String(record.mileage)
        costText = record.cost == 0 ? "" : String(record.cost)
        notes = record.notes
        receiptPhotoData = record.receiptPhotoData
        if let dueMileage = record.nextDueMileage {
            setReminder = true
            nextDueMileageText = String(dueMileage)
        }
        if let dueDate = record.nextDueDate {
            setReminder = true
            nextDueDate = dueDate
        }
        // If the title doesn't match any standard type name, it was likely a
        // custom "Other" description — restore it into that field.
        if type == .other && title != MaintenanceType.other.rawValue {
            otherTypeDescription = title
        }
    }

    private func save() {
        let mileage = Int(mileageText) ?? 0
        let cost = Double(costText) ?? 0
        let nextDueMileage = Int(nextDueMileageText) ?? 0

        // If "Other" was picked, use the free-text description as the title
        // (unless the user also typed a specific Title, which wins).
        var finalTitle = title
        if finalTitle.isEmpty && type == .other && !otherTypeDescription.isEmpty {
            finalTitle = otherTypeDescription
        }

        if let record {
            record.type = type
            record.title = finalTitle.isEmpty ? type.rawValue : finalTitle
            record.date = date
            record.mileage = mileage
            record.cost = cost
            record.notes = notes
            record.receiptPhotoData = receiptPhotoData
            record.nextDueMileage = setReminder ? nextDueMileage : nil
            record.nextDueDate = setReminder ? nextDueDate : nil
        } else {
            let newRecord = MaintenanceRecord(
                type: type,
                title: finalTitle,
                date: date,
                mileage: mileage,
                cost: cost,
                notes: notes,
                nextDueMileage: setReminder ? nextDueMileage : nil,
                nextDueDate: setReminder ? nextDueDate : nil,
                receiptPhotoData: receiptPhotoData
            )
            newRecord.vehicle = vehicle
            context.insert(newRecord)
        }

        if mileage > vehicle.currentMileage {
            vehicle.currentMileage = mileage
        }
        dismiss()
    }

    private func deleteAndDismiss() {
        if let record {
            context.delete(record)
        }
        dismiss()
    }
}
