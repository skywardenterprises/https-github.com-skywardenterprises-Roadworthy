import SwiftUI
import SwiftData

struct SpecListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @State private var specToEdit: VehicleSpec?
    @State private var pendingDeletion: [VehicleSpec] = []
    @State private var saveError: String?

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
                    "No Specs Saved Yet",
                    systemImage: "list.clipboard.fill",
                    description: Text("Save part numbers and torque specs here so you're never digging through old receipts again.")
                )
            } else {
                List {
                    if !parts.isEmpty {
                        Section("Parts") {
                            ForEach(parts) { spec in
                                specRow(spec)
                            }
                            .onDelete { offsets in pendingDeletion = offsets.map { parts[$0] } }
                        }
                    }
                    if !torqueSpecs.isEmpty {
                        Section("Torque Specs") {
                            ForEach(torqueSpecs) { spec in
                                specRow(spec)
                            }
                            .onDelete { offsets in pendingDeletion = offsets.map { torqueSpecs[$0] } }
                        }
                    }
                }
            }
        }
        .navigationTitle("Vehicle Specs")
        .navigationBarTitleDisplayMode(.inline)
        .confirmDeletion(of: $pendingDeletion, noun: "spec") { deleteSpecs($0) }
        .saveErrorAlert($saveError)
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

    private func deleteSpecs(_ specs: [VehicleSpec]) {
        for spec in specs {
            context.delete(spec)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
    }
}
