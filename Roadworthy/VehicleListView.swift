import SwiftUI
import SwiftData

struct VehicleListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Vehicle> { $0.isActive == true }, sort: \Vehicle.nickname)
    private var vehicles: [Vehicle]
    @Query(filter: #Predicate<Vehicle> { $0.isActive == false }, sort: \Vehicle.nickname)
    private var inactiveVehicles: [Vehicle]
    @State private var showingAddVehicle = false
    @State private var showingSettings = false
    @State private var vehiclePendingDeletion: Vehicle?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(vehicles) { vehicle in
                    NavigationLink {
                        VehicleDetailView(vehicle: vehicle)
                    } label: {
                        VehicleRow(vehicle: vehicle)
                    }
                }
                .onDelete { offsets in
                    vehiclePendingDeletion = offsets.first.map { vehicles[$0] }
                }

                if !inactiveVehicles.isEmpty {
                    Section {
                        NavigationLink {
                            InactiveVehiclesView()
                        } label: {
                            Label(
                                "Inactive Vehicles (\(inactiveVehicles.count))",
                                systemImage: "archivebox"
                            )
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if vehicles.isEmpty && inactiveVehicles.isEmpty {
                    ContentUnavailableView(
                        "Let's Get You On the Road",
                        systemImage: "car.fill",
                        description: Text("Add your first vehicle to start tracking maintenance, fuel, and more.")
                    )
                }
            }
            .navigationTitle("Roadworthy")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddVehicle = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Vehicle")
                }
            }
            .confirmationDialog(
                "Delete \(vehiclePendingDeletion?.displayName ?? "this vehicle")?",
                isPresented: Binding(
                    get: { vehiclePendingDeletion != nil },
                    set: { if !$0 { vehiclePendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: vehiclePendingDeletion
            ) { vehicle in
                Button("Mark Inactive Instead") { markInactive(vehicle) }
                Button("Delete Vehicle and All History", role: .destructive) { deleteVehicle(vehicle) }
                Button("Cancel", role: .cancel) {}
            } message: { vehicle in
                Text("This permanently deletes \(vehicle.displayName) and all \(historyCount(vehicle)) of its logs, photos, and documents from all your devices. Marking it inactive keeps everything and moves it to Inactive Vehicles.")
            }
            .saveErrorAlert($saveError)
            .sheet(isPresented: $showingAddVehicle) {
                AddEditVehicleView(vehicle: nil)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private func historyCount(_ vehicle: Vehicle) -> Int {
        vehicle.fuelLogs.count + vehicle.maintenanceRecords.count + vehicle.expenses.count
            + vehicle.trips.count + vehicle.reminders.count + vehicle.documents.count + vehicle.specs.count
    }

    private func markInactive(_ vehicle: Vehicle) {
        vehicle.isActive = false
        vehicle.inactiveDate = .now
        if let message = context.saveReportingErrors() {
            saveError = message
            return
        }
        Haptics.success()
    }

    /// Deleting a vehicle cascades to its entire history and syncs to every
    /// device, so it's confirmed first. Its reminders' pending notifications
    /// are cancelled so none fire for a vehicle that no longer exists.
    private func deleteVehicle(_ vehicle: Vehicle) {
        let reminders = vehicle.reminders
        let vehicleName = vehicle.displayName
        reminders.forEach { ReminderNotificationManager.cancel(for: $0) }
        context.delete(vehicle)
        if let message = context.saveReportingErrors() {
            // Rolled back, so the vehicle and its notifications are restored.
            reminders.forEach { ReminderNotificationManager.schedule(for: $0, vehicleName: vehicleName) }
            saveError = message
            return
        }
        Haptics.delete()
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles

    var body: some View {
        HStack(spacing: 12) {
            if let data = vehicle.photoData, let uiImage = ThumbnailCache.image(for: data, maxPixel: 150) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .overlay(Image(systemName: vehicle.vehicleType.iconName).foregroundStyle(.secondary))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.displayName)
                    .font(.headline)
                Text(String(vehicle.year) + " " + vehicle.make + " " + vehicle.model)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formattedDistance(vehicle.currentMileage, unit: distanceUnit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VehicleListView()
        .modelContainer(for: [Vehicle.self], inMemory: true)
}
