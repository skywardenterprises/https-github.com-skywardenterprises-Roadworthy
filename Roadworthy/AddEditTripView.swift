import SwiftUI
import SwiftData

struct AddEditTripView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles

    // If editing an existing trip, pass it in. Nil means "creating new".
    var trip: TripLog?

    @State private var date = Date.now
    @State private var startMileageText = ""
    @State private var endMileageText = ""
    @State private var purpose: TripPurpose = .business
    @State private var businessPurposeNote = ""
    @State private var fromLocation = ""
    @State private var toLocation = ""

    @State private var showingValidationAlert = false
    @State private var validationTitle = ""
    @State private var validationMessage = ""
    @State private var showingDeleteConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var didLoad = false
    @State private var saveError: String?
    @State private var loadedDraft: [AnyHashable] = []

    private var isEditing: Bool { trip != nil }

    private var enteredStart: Int? { DigitsField.value(of: startMileageText) }
    private var enteredEnd: Int? { DigitsField.value(of: endMileageText) }

    /// Distance in the person's display unit, for the Distance row.
    private var displayedDistance: Int {
        max(0, (enteredEnd ?? 0) - (enteredStart ?? 0))
    }

    private var validationIssue: String? {
        guard let start = enteredStart, let end = enteredEnd else {
            return "Enter the start and end odometer readings to save."
        }
        if end <= start {
            return "The end odometer must be higher than the start."
        }
        // Distances are stored in whole miles, so a very short trip entered
        // in kilometers can round to zero.
        if convertToMiles(end, from: distanceUnit) <= convertToMiles(start, from: distanceUnit) {
            return "Trips shorter than 1 mile can't be saved, because distances are stored in whole miles."
        }
        if purpose == .business && businessPurposeNote.trimmed.isEmpty {
            return "Enter the business purpose. The IRS requires one for each business trip."
        }
        return nil
    }

    private var draft: [AnyHashable] {
        formSnapshot(date, enteredStart, enteredEnd, purpose, businessPurposeNote, fromLocation, toLocation)
    }

    private var hasChanges: Bool { didLoad && draft != loadedDraft }

    var body: some View {
        NavigationStack {
            Form {
                if didLoad, let validationIssue {
                    Section { FormIssueRow(message: validationIssue) }
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    DigitsField(
                        label: "Start Odometer (\(distanceUnit.rawValue))",
                        placeholder: "Start Odometer",
                        text: $startMileageText
                    )
                    DigitsField(
                        label: "End Odometer (\(distanceUnit.rawValue))",
                        placeholder: "End Odometer",
                        text: $endMileageText
                    )
                    if displayedDistance > 0 {
                        LabeledContent("Distance", value: "\(displayedDistance.formatted()) \(distanceUnit.rawValue)")
                    }
                }

                Section {
                    Picker("Purpose", selection: $purpose) {
                        ForEach(TripPurpose.allCases) { purpose in
                            Text(purpose.rawValue).tag(purpose)
                        }
                    }
                    .pickerStyle(.segmented)
                    if purpose == .business {
                        TextField("Business Purpose (required)", text: $businessPurposeNote, axis: .vertical)
                    }
                } footer: {
                    if purpose == .business {
                        Text("The IRS requires a documented business purpose for each trip, like \"Client meeting downtown\" or \"Parts pickup.\"")
                    }
                }

                Section("Locations (Optional)") {
                    TextField("From", text: $fromLocation)
                    TextField("To", text: $toLocation)
                }

                if isEditing {
                    Section {
                        Button("Delete Trip", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                        .deleteConfirmation("Delete this trip?", isPresented: $showingDeleteConfirm) {
                            deleteAndDismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Trip" : "Log Trip")
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
        guard let trip else {
            startMileageText = vehicle.currentMileage == 0 ? "" : String(convertFromMiles(vehicle.currentMileage, to: distanceUnit))
            return
        }
        date = trip.date
        startMileageText = String(convertFromMiles(trip.startMileage, to: distanceUnit))
        endMileageText = String(convertFromMiles(trip.endMileage, to: distanceUnit))
        purpose = trip.purpose
        businessPurposeNote = trip.businessPurposeNote
        fromLocation = trip.fromLocation
        toLocation = trip.toLocation
    }

    private func save() {
        guard validationIssue == nil, let startValue = enteredStart, let endValue = enteredEnd else { return }
        let start = convertToMiles(startValue, from: distanceUnit)
        let end = convertToMiles(endValue, from: distanceUnit)

        // Same date rules as fuel and maintenance, plus a check that the trip's
        // readings fit with fuel and maintenance logs on other days.
        if let problem = EntryValidation.dateProblem(date, vehicle: vehicle)
            ?? EntryValidation.tripProblem(date: date, start: start, end: end, vehicle: vehicle, unit: distanceUnit) {
            validationTitle = problem.title
            validationMessage = problem.message
            showingValidationAlert = true
            return
        }

        let note = purpose == .business ? businessPurposeNote.trimmed : ""
        if let trip {
            trip.date = date
            trip.startMileage = start
            trip.endMileage = end
            trip.purpose = purpose
            trip.businessPurposeNote = note
            trip.fromLocation = fromLocation.trimmed
            trip.toLocation = toLocation.trimmed
        } else {
            let newTrip = TripLog(
                date: date,
                startMileage: start,
                endMileage: end,
                purpose: purpose,
                businessPurposeNote: note,
                fromLocation: fromLocation.trimmed,
                toLocation: toLocation.trimmed
            )
            newTrip.vehicle = vehicle
            context.insert(newTrip)
        }

        if end > vehicle.currentMileage {
            vehicle.currentMileage = end
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.success()
        dismiss()
    }

    private func deleteAndDismiss() {
        if let trip {
            context.delete(trip)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
        dismiss()
    }
}
