import SwiftUI
import SwiftData

struct SpecListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var specToEdit: VehicleSpec?

    private var parts: [VehicleSpec] {
        vehicle.specs.filter { $0.category == .part }.sorted { $0.name < $1.name }
    }
    private var torqueSpecs: [VehicleSpec] {
        vehicle.specs.filter { $0.category == .torque }.sorted { $0.name < $1.name }
    }

    var body: some View {
        Group {
            if vehicle.specs.isEmpty {
                ContentUnavailableView(
                    "No Specs Saved",
                    systemImage: "list.clipboard",
                    description: Text("Use the + button to save part numbers and torque specs for quick reference.")
                )
            } else {
                List {
                    if !parts.isEmpty {
                        Section("Parts") {
                            ForEach(parts) { spec in
                                specRow(spec)
                            }
                            .onDelete { offsets in deleteSpecs(parts, at: offsets) }
                        }
                    }
                    if !torqueSpecs.isEmpty {
                        Section("Torque Specs") {
                            ForEach(torqueSpecs) { spec in
                                specRow(spec)
                            }
                            .onDelete { offsets in deleteSpecs(torqueSpecs, at: offsets) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Vehicle Specs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $specToEdit) { spec in
            AddEditSpecView(vehicle: vehicle, spec: spec)
        }
    }

    private func specRow(_ spec: VehicleSpec) -> some View {
        Button {
            specToEdit = spec
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.name).font(.headline)
                    if !spec.brand.isEmpty {
                        Text(spec.brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !spec.notes.isEmpty {
                        Text(spec.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !spec.value.isEmpty {
                    Text(spec.value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func deleteSpecs(_ list: [VehicleSpec], at offsets: IndexSet) {
        for index in offsets {
            context.delete(list[index])
        }
    }
}

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

    private var isEditing: Bool { spec != nil }
    private var presetOptions: [String] {
        category == .part ? partPresets : torquePresets
    }
    private var finalName: String {
        presetName == Self.customOption ? customName : presetName
    }
    private var finalValue: String {
        if category == .torque {
            return torqueMagnitude.isEmpty ? "" : "\(torqueMagnitude) \(torqueUnit)"
        }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(SpecCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
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
                            deleteAndDismiss()
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Spec" : "New Spec")
            .navigationBarTitleDisplayMode(.inline)
            .withKeyboardDismiss()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(finalName.isEmpty)
                }
            }
            .onAppear(perform: loadExistingValues)
            .onChange(of: category) { _, _ in
                // Reset the item picker to a valid option for the newly selected category.
                presetName = presetOptions.first ?? Self.customOption
            }
        }
    }

    private func loadExistingValues() {
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
        if let spec {
            spec.category = category
            spec.name = finalName
            spec.value = finalValue
            spec.brand = category == .part ? brand : ""
            spec.notes = notes
        } else {
            let newSpec = VehicleSpec(
                category: category,
                name: finalName,
                value: finalValue,
                brand: category == .part ? brand : "",
                notes: notes
            )
            newSpec.vehicle = vehicle
            context.insert(newSpec)
        }
        dismiss()
    }

    private func deleteAndDismiss() {
        if let spec {
            context.delete(spec)
        }
        dismiss()
    }
}
