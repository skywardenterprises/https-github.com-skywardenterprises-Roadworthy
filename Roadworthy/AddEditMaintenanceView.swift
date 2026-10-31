import SwiftUI
import SwiftData

struct AddEditMaintenanceView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles

    // Every maintenance record across every vehicle, most recent first —
    // used to build the Shop Name suggestions. The same shop often services
    // more than one vehicle, so this isn't scoped to the current vehicle.
    //
    // Limited to the 200 most recent records and to the two fields the
    // suggestions need, instead of fetching every record in the app.
    @Query(Self.shopHistoryDescriptor) private var allMaintenanceRecords: [MaintenanceRecord]

    private static var shopHistoryDescriptor: FetchDescriptor<MaintenanceRecord> {
        var descriptor = FetchDescriptor<MaintenanceRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.propertiesToFetch = [\.shopName, \.date]
        descriptor.fetchLimit = 200
        return descriptor
    }

    private var shopNameHistory: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in allMaintenanceRecords {
            let name = record.shopName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !seen.contains(name.lowercased()) else { continue }
            seen.insert(name.lowercased())
            result.append(name)
        }
        return result
    }

    // If editing an existing record, pass it in. Nil means "creating new".
    var record: MaintenanceRecord?

    @State private var selectedType: MaintenanceType?
    /// Reads as Custom until a type is chosen; validation blocks saving
    /// before that, so the fallback is never stored.
    private var type: MaintenanceType {
        get { selectedType ?? .other }
        nonmutating set { selectedType = newValue }
    }
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
        if selectedType == nil {
            return L("Choose a maintenance type to save.")
        }
        if requiresOdometer && enteredMileage == nil {
            return L("Enter the odometer reading to save.")
        }
        if dueByMileage {
            guard let due = enteredNextDueMileage, due > 0 else {
                return L("Enter the next due odometer reading, or turn off Due by Odometer.")
            }
            if let mileage = enteredMileage, due <= mileage {
                return L("The next due odometer reading must be higher than this service's reading.")
            }
        }
        if dueByDate,
           Calendar.current.startOfDay(for: nextDueDate) <= Calendar.current.startOfDay(for: date) {
            return L("The next due date must be after the service date.")
        }
        if isLoadingPhoto {
            return L("Waiting for the receipt photo to finish loading…")
        }
        return nil
    }

    private var draft: [AnyHashable] {
        formSnapshot(
            selectedType?.rawValue ?? "", title, otherTypeDescription, date, DigitsField.value(of: mileageText),
            Double(costText), shopName, notes, receiptPhotoData,
            dueByDate, nextDueDate, dueByMileage, DigitsField.value(of: nextDueMileageText)
        )
    }

    private var hasChanges: Bool { didLoad && draft != loadedDraft }

    private static let nextDueDateRowID = "nextDueDateRow"
    private static let nextDueMileageRowID = "nextDueMileageRow"

    /// Waits a moment for the new row to appear, then scrolls it into view.
    private func scroll(to id: String, with proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation { proxy.scrollTo(id, anchor: .center) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                if didLoad, let validationIssue {
                    Section { FormIssueRow(message: validationIssue) }
                }

                Section {
                    LabeledContent("Type") {
                        Menu {
                            ForEach(MaintenanceType.pickerOrder) { option in
                                Button {
                                    selectedType = option
                                } label: {
                                    if selectedType == option {
                                        Label(option.menuName, systemImage: "checkmark")
                                    } else {
                                        Text(option.menuName)
                                    }
                                }
                            }
                        } label: {
                            if let selectedType {
                                Text(selectedType.displayName)
                            } else {
                                Text("-select-").foregroundStyle(Color(.tertiaryLabel))
                            }
                        }
                    }
                    if selectedType == .other {
                        TextField("Describe the maintenance type", text: $otherTypeDescription)
                    }
                    TextField("Title (optional)", text: $title)
                    WheelDatePicker(title: "Date", date: $date)
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
                    AutocompleteField(title: "Shop Name (optional)", text: $shopName, history: shopNameHistory)
                    ReceiptPhotoField(photoData: $receiptPhotoData, isLoading: $isLoadingPhoto)
                }

                Section {
                    Toggle("Due by Date", isOn: $dueByDate)
                    if dueByDate {
                        WheelDatePicker(title: "Next Due Date", date: $nextDueDate)
                            .id(Self.nextDueDateRowID)
                    }
                    Toggle("Due by Odometer", isOn: $dueByMileage)
                    if dueByMileage {
                        DigitsField(
                            label: "Next Due (\(distanceUnit.rawValue))",
                            placeholder: "Odometer",
                            text: $nextDueMileageText
                        )
                        .id(Self.nextDueMileageRowID)
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
            // Turning on a Next Due option reveals a field below the toggle.
            // Scroll so it's on screen instead of leaving it off the bottom.
            .onChange(of: dueByDate) { _, isOn in
                if isOn { scroll(to: Self.nextDueDateRowID, with: proxy) }
            }
            .onChange(of: dueByMileage) { _, isOn in
                if isOn { scroll(to: Self.nextDueMileageRowID, with: proxy) }
            }
            }
            .navigationTitle(LocalizedStringKey(isEditing ? "Edit Maintenance" : "Log Maintenance"))
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
            record.shopName = shopName.normalizedPlaceName(history: shopNameHistory)
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
                shopName: shopName.normalizedPlaceName(history: shopNameHistory),
                notes: notes,
                nextDueMileage: nextDueMileage,
                nextDueDate: nextDueDateValue,
                receiptPhotoData: receiptPhotoData
            )
            newRecord.vehicle = vehicle
            context.insert(newRecord)
        }

        // Saving an entry with a reading restarts the 30-day odometer check-in clock,
        // even if the entry itself is dated further back.
        if mileage > 0 { vehicle.odometerUpdatedDate = .now }
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
