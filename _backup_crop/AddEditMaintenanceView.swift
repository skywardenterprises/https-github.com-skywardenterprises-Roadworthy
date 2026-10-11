import SwiftUI
import SwiftData

struct AddEditMaintenanceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles

    // If editing an existing record, pass it in. Nil means "creating new".
    var record: MaintenanceRecord?

    @State private var type: MaintenanceType = .oilChange
    @State private var title = ""
    @State private var otherTypeDescription = ""
    @State private var date = Date.now
    @State private var mileageText = ""
    @State private var costText = ""
    @State private var shopName = ""
    @State private var notes = ""
    @State private var receiptPhotoData: Data?
    @State private var isLoadingPhoto = false

    // Next due: date and odometer are independent, so a mileage-only or
    // date-only reminder is possible.
    @State private var dueByDate = false
    @State private var nextDueDate = Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now
    @State private var dueByMileage = false
    @State private var nextDueMileageText = ""

    @State private var showingValidationAlert = false
    @State private var validationTitle = ""
    @State private var validationMessage = ""
    @State private var showingDeleteConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var didLoad = false
    @State private var saveError: String?
    @State private var loadedDraft: [AnyHashable] = []

    private var isEditing: Bool { record != nil }

    /// Registration renewals often have no odometer reading. Every other type
    /// needs one.
    private var requiresOdometer: Bool { type != .registration }

    private var enteredMileage: Int? {
        DigitsField.value(of: mileageText).map { convertToMiles($0, from: distanceUnit) }
    }

    private var enteredNextDueMileage: Int? {
        DigitsField.value(of: nextDueMileageText).map { convertToMiles($0, from: distanceUnit) }
    }

    private var validationIssue: String? {
        if requiresOdometer && enteredMileage == nil {
            return "Enter the odometer reading to save."
        }
        if dueByMileage {
            guard let due = enteredNextDueMileage, due > 0 else {
                return "Enter the next due odometer reading, or turn off Due by Odometer."
            }
            if let mileage = enteredMileage, due <= mileage {
                return "The next due odometer reading must be higher than this service's reading."
            }
        }
        if dueByDate,
           Calendar.current.startOfDay(for: nextDueDate) <= Calendar.current.startOfDay(for: date) {
            return "The next due date must be after the service date."
        }
        if isLoadingPhoto {
            return "Waiting for the receipt photo to finish loading…"
        }
        return nil
    }

    private var draft: [AnyHashable] {
        formSnapshot(
            type, title, otherTypeDescription, date, DigitsField.value(of: mileageText),
            Double(costText), shopName, notes, receiptPhotoData,
            dueByDate, nextDueDate, dueByMileage, DigitsField.value(of: nextDueMileageText)
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
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DigitsField(
                        label: "Odometer (\(distanceUnit.rawValue))",
                        placeholder: requiresOdometer ? "Odometer" : "Optional",
                        text: $mileageText
                    )
                    HStack {
                        Text("Cost")
                        Spacer()
                        AutoDecimalField(title: "Cost", text: $costText)
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                    TextField("Shop Name (optional)", text: $shopName)
                    ReceiptPhotoField(photoData: $receiptPhotoData, isLoading: $isLoadingPhoto)
                }

                Section {
                    Toggle("Due by Date", isOn: $dueByDate)
                    if dueByDate {
                        DatePicker("Next Due Date", selection: $nextDueDate, displayedComponents: .date)
                    }
                    Toggle("Due by Odometer", isOn: $dueByMileage)
                    if dueByMileage {
                        DigitsField(
                            label: "Next Due (\(distanceUnit.rawValue))",
                            placeholder: "Odometer",
                            text: $nextDueMileageText
                        )
                    }
                } header: {
                    Text("Next Due (Optional)")
                }

                if isEditing {
                    Section {
                        Button("Delete Maintenance Record", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                        .deleteConfirmation("Delete this maintenance record?", isPresented: $showingDeleteConfirm) {
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
            .saveErrorAlert($saveError)
            .discardChangesGuard(hasChanges: hasChanges, isConfirming: $showingDiscardConfirm) { dismiss() }
            .alert(validationTitle, isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func loadExistingValues() {
        guard !didLoad else { return }
        defer {
            loadedDraft = draft
            didLoad = true
        }
        guard let record else { return }
        type = record.type
        // A record saved without a title stores the type name as its title.
        // Loading that into the Title field would make it look typed, and it
        // would then stay behind if the type changed. For custom types, the
        // stored title is the description.
        if record.type == .other, record.title != MaintenanceType.other.rawValue {
            otherTypeDescription = record.title
            title = ""
        } else {
            title = record.title == record.type.rawValue ? "" : record.title
        }
        date = record.date
        mileageText = record.mileage == 0 ? "" : String(convertFromMiles(record.mileage, to: distanceUnit))
        costText = record.cost == 0 ? "" : String(record.cost)
        shopName = record.shopName
        notes = record.notes
        receiptPhotoData = record.receiptPhotoData
        if let dueMileage = record.nextDueMileage, dueMileage > 0 {
            dueByMileage = true
            nextDueMileageText = String(convertFromMiles(dueMileage, to: distanceUnit))
        }
        if let dueDate = record.nextDueDate {
            dueByDate = true
            nextDueDate = dueDate
        }
    }

    private func showProblem(_ problem: EntryProblem) {
        validationTitle = problem.title
        validationMessage = problem.message
        showingValidationAlert = true
    }

    private func save() {
        guard validationIssue == nil else { return }
        let mileage = enteredMileage ?? 0
        let cost = Double(costText) ?? 0

        if let problem = EntryValidation.dateProblem(date, vehicle: vehicle)
            ?? EntryValidation.mileageProblem(date: date, mileage: mileage, vehicle: vehicle, excludingMaintenanceRecord: record) {
            showProblem(problem)
            return
        }

        var finalTitle = title.trimmed
        if finalTitle.isEmpty && type == .other {
            finalTitle = otherTypeDescription.trimmed
        }
        if finalTitle.isEmpty {
            finalTitle = type.rawValue
        }
        let nextDueMileage = dueByMileage ? enteredNextDueMileage : nil
        let nextDueDateValue = dueByDate ? nextDueDate : nil

        if let record {
            record.type = type
            record.title = finalTitle
            record.date = date
            record.mileage = mileage
            record.cost = cost
            record.shopName = shopName.trimmed
            record.notes = notes
            record.receiptPhotoData = receiptPhotoData
            record.nextDueMileage = nextDueMileage
            record.nextDueDate = nextDueDateValue
        } else {
            let newRecord = MaintenanceRecord(
                type: type,
                title: finalTitle,
                date: date,
                mileage: mileage,
                cost: cost,
                shopName: shopName.trimmed,
                notes: notes,
                nextDueMileage: nextDueMileage,
                nextDueDate: nextDueDateValue,
                receiptPhotoData: receiptPhotoData
            )
            newRecord.vehicle = vehicle
            context.insert(newRecord)
        }

        if mileage > vehicle.currentMileage {
            vehicle.currentMileage = mileage
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.success()
        dismiss()
    }

    private func deleteAndDismiss() {
        if let record {
            context.delete(record)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
        dismiss()
    }
}
