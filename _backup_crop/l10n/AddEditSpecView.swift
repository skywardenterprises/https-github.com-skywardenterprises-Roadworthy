import SwiftUI
import SwiftData

struct AddEditSpecView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    // If editing an existing spec, pass it in. Nil means "creating new".
    var spec: VehicleSpec?

    private static let customOption = "Custom…"
    private static let torqueUnits = ["ft-lb", "in-lb", "Nm", "kgf·m"]

    private var partPresets: [String] {
        switch vehicle.vehicleType {
        case .motorcycle:
            return [
                "Oil Filter", "Air Filter", "Spark Plugs",
                "Chain & Sprocket Kit", "Drive Belt",
                "Brake Pads (Front)", "Brake Pads (Rear)", "Battery",
                Self.customOption
            ]
        default:
            return [
                "Oil Filter", "Air Filter", "Cabin Air Filter",
                "Brake Pads (Front)", "Brake Pads (Rear)",
                "Brake Rotors (Front)", "Brake Rotors (Rear)",
                "Spark Plugs", "Serpentine Belt", "Battery",
                "Wiper Blades (Front)", "Wiper Blade (Rear)", Self.customOption
            ]
        }
    }

    private var torquePresets: [String] {
        switch vehicle.vehicleType {
        case .motorcycle:
            return [
                "Front Axle Nut", "Rear Axle Nut",
                "Front Brake Caliper", "Rear Brake Caliper",
                "Chain Slack", "Oil Drain Plug", "Spark Plugs", Self.customOption
            ]
        default:
            return [
                "Wheel Lug Nuts", "Oil Drain Plug", "Spark Plugs",
                "Oil Filter Housing Cap", Self.customOption
            ]
        }
    }

    @State private var category: SpecCategory = .part
    @State private var presetName: String = ""
    @State private var customName = ""
    @State private var value = ""
    @State private var brand = ""
    @State private var torqueMagnitude = ""
    @State private var torqueUnit: String = AddEditSpecView.torqueUnits.first!
    @State private var notes = ""

    @State private var showingDeleteConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var didLoad = false
    @State private var saveError: String?
    @State private var loadedDraft: [AnyHashable] = []

    private var isEditing: Bool { spec != nil }
    private var presetOptions: [String] {
        category == .part ? partPresets : torquePresets
    }
    private var finalName: String {
        (presetName == Self.customOption ? customName : presetName).trimmed
    }
    private var finalValue: String {
        if category == .torque {
            let magnitude = torqueMagnitude.trimmed
            return magnitude.isEmpty ? "" : "\(magnitude) \(torqueUnit)"
        }
        return value.trimmed
    }

    private var validationIssue: String? {
        if finalName.isEmpty {
            return presetName == Self.customOption ? "Enter a name for this item." : "Choose an item."
        }
        return nil
    }

    private var draft: [AnyHashable] {
        formSnapshot(category, presetName, customName, value, brand, torqueMagnitude, torqueUnit, notes)
    }

    private var hasChanges: Bool { didLoad && draft != loadedDraft }

    var body: some View {
        NavigationStack {
            Form {
                if didLoad, let validationIssue {
                    Section { FormIssueRow(message: validationIssue) }
                }

                Section {
                    Picker("Category", selection: $category) {
                        ForEach(SpecCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                    Picker("Item", selection: $presetName) {
                        ForEach(presetOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    if presetName == Self.customOption {
                        TextField("Name", text: $customName)
                    }

                    if category == .torque {
                        HStack {
                            TextField("Value", text: $torqueMagnitude)
                                .keyboardType(.decimalPad)
                            Picker("Unit", selection: $torqueUnit) {
                                ForEach(Self.torqueUnits, id: \.self) { unit in
                                    Text(unit).tag(unit)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    } else {
                        TextField("Brand (e.g. Bosch, Fram)", text: $brand)
                        TextField("Part Number", text: $value)
                    }

                    TextField("Notes", text: $notes, axis: .vertical)
                }

                if isEditing {
                    Section {
                        Button("Delete Spec", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                        .deleteConfirmation("Delete this spec?", isPresented: $showingDeleteConfirm) {
                            deleteAndDismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Spec" : "Add Spec")
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
            .onChange(of: category) { _, _ in
                // Only reset the item picker when the current choice doesn't
                // exist for the new category. Loading an existing torque spec
                // changes the category from its .part default, and resetting
                // unconditionally here used to replace the spec's name.
                if !presetOptions.contains(presetName) {
                    presetName = presetOptions.first ?? Self.customOption
                }
            }
        }
    }

    private func loadExistingValues() {
        guard !didLoad else { return }
        defer {
            loadedDraft = draft
            didLoad = true
        }
        guard let spec else {
            presetName = presetOptions.first ?? Self.customOption
            return
        }
        category = spec.category
        notes = spec.notes
        if presetOptions.contains(spec.name) {
            presetName = spec.name
        } else {
            presetName = Self.customOption
            customName = spec.name
        }

        if spec.category == .torque {
            // Try to split "89 ft-lb" back into a magnitude and a known unit.
            let parts = spec.value.split(separator: " ")
            if let last = parts.last, Self.torqueUnits.contains(String(last)) {
                torqueUnit = String(last)
                torqueMagnitude = parts.dropLast().joined(separator: " ")
            } else {
                torqueMagnitude = spec.value
            }
        } else {
            value = spec.value
            brand = spec.brand
        }
    }

    private func save() {
        guard validationIssue == nil else { return }
        if let spec {
            spec.category = category
            spec.name = finalName
            spec.value = finalValue
            spec.brand = category == .part ? brand.trimmed : ""
            spec.notes = notes
        } else {
            let newSpec = VehicleSpec(
                category: category,
                name: finalName,
                value: finalValue,
                brand: category == .part ? brand.trimmed : "",
                notes: notes
            )
            newSpec.vehicle = vehicle
            context.insert(newSpec)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.success()
        dismiss()
    }

    private func deleteAndDismiss() {
        if let spec {
            context.delete(spec)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
        dismiss()
    }
}
