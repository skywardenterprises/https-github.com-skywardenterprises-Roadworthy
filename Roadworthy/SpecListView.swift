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
    private static let partPresets = [
        "Oil Filter", "Air Filter", "Cabin Air Filter",
        "Brake Pads (Front)", "Brake Pads (Rear)",
        "Brake Rotors (Front)", "Brake Rotors (Rear)",
        "Spark Plugs", "Serpentine Belt", "Battery",
        "Wiper Blades (Front)", "Wiper Blade (Rear)", customOption
    ]
    private static let torquePresets = [
        "Wheel Lug Nuts", "Oil Drain Plug", "Spark Plugs",
        "Oil Filter Housing Cap", customOption
    ]

    @State private var category: SpecCategory = .part
    @State private var presetName: String = AddEditSpecView.partPresets.first!
    @State private var customName = ""
    @State private var value = ""
    @State private var notes = ""

    private var isEditing: Bool { spec != nil }
    private var presetOptions: [String] {
        category == .part ? Self.partPresets : Self.torquePresets
    }
    private var finalName: String {
        presetName == Self.customOption ? customName : presetName
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
                    TextField(
                        category == .part ? "Part Number" : "Torque Value (e.g. 89 ft-lb)",
                        text: $value
                    )
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
        guard let spec else { return }
        category = spec.category
        value = spec.value
        notes = spec.notes
        if presetOptions.contains(spec.name) {
            presetName = spec.name
        } else {
            presetName = Self.customOption
            customName = spec.name
        }
    }

    private func save() {
        if let spec {
            spec.category = category
            spec.name = finalName
            spec.value = value
            spec.notes = notes
        } else {
            let newSpec = VehicleSpec(category: category, name: finalName, value: value, notes: notes)
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
