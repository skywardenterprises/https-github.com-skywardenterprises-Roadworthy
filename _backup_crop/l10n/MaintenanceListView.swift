import SwiftUI
import SwiftData

struct MaintenanceListView: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles
    @State private var recordToEdit: MaintenanceRecord?
    @State private var pendingDeletion: [MaintenanceRecord] = []
    @State private var saveError: String?

    private var sortedRecords: [MaintenanceRecord] {
        vehicle.maintenanceRecords.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sortedRecords.isEmpty {
                ContentUnavailableView(
                    "No Maintenance Yet",
                    systemImage: "wrench.and.screwdriver.fill",
                    description: Text("Oil changes, tire rotations, brake jobs — build your vehicle's service history here.")
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
                                    Text(record.cost, format: .currency(code: AppCurrency.code))
                                        .foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text(record.date.formatted(date: .abbreviated, time: .omitted))
                                    Text("•")
                                    Text(formattedDistance(record.mileage, unit: distanceUnit))
                                    if !record.shopName.isEmpty {
                                        Text("•")
                                        Text(record.shopName)
                                    }
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
                    .onDelete { offsets in pendingDeletion = offsets.map { sortedRecords[$0] } }
                }
            }
        }
        .navigationTitle("Maintenance")
        .navigationBarTitleDisplayMode(.inline)
        .confirmDeletion(of: $pendingDeletion, noun: "maintenance record") { deleteRecords($0) }
        .saveErrorAlert($saveError)
        .sheet(item: $recordToEdit) { record in
            AddEditMaintenanceView(vehicle: vehicle, record: record)
        }
    }

    private func deleteRecords(_ records: [MaintenanceRecord]) {
        for record in records {
            context.delete(record)
        }
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.delete()
    }
}
