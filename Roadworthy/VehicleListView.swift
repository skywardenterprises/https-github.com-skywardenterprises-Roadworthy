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
                        VehicleCardRow(vehicle: vehicle)
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .rwCardRow()
                }
                .onDelete { offsets in
                    vehiclePendingDeletion = offsets.first.map { vehicles[$0] }
                }

                if !inactiveVehicles.isEmpty {
                    NavigationLink {
                        InactiveVehiclesView()
                    } label: {
                        HStack {
                            Label(
                                LocalizedStringKey("Inactive Vehicles (\(inactiveVehicles.count))"),
                                systemImage: "archivebox"
                            )
                            .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .navigationLinkIndicatorVisibility(.hidden)
                    .rwCardRow()
                }

                if !vehicles.isEmpty || !inactiveVehicles.isEmpty {
                    RoadworthyBrandFooter()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(RWColor.background)
            .overlay {
                if vehicles.isEmpty && inactiveVehicles.isEmpty {
                    ContentUnavailableView {
                        Label("Welcome to Roadworthy", systemImage: "car.fill")
                    } description: {
                        Text("Your garage starts here. Add your first vehicle to begin tracking maintenance, fuel, expenses, and more.")
                    } actions: {
                        Button("Add Vehicle") { showingAddVehicle = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Vehicles")
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
            .alert(
                "Delete \(vehiclePendingDeletion?.displayName ?? "this vehicle")?",
                isPresented: Binding(
                    get: { vehiclePendingDeletion != nil },
                    set: { if !$0 { vehiclePendingDeletion = nil } }
                ),
                presenting: vehiclePendingDeletion
            ) { vehicle in
                Button("Cancel", role: .cancel) {}
                Button("Mark Inactive Instead") { markInactive(vehicle) }
                Button("Delete Vehicle and All History", role: .destructive) { deleteVehicle(vehicle) }
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

struct VehicleCardRow: View {
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let compact = typeSize.isAccessibilitySize
        let layout = compact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            thumbnail(width: compact ? 88 : 110, height: compact ? 56 : 70)

            VStack(alignment: .leading, spacing: 3) {
                Text(vehicle.displayName)
                    .font(.headline)
                Text(String(vehicle.year) + " " + vehicle.make + " " + vehicle.model)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(formattedDistance(vehicle.currentMileage, unit: distanceUnit))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !compact {
                Spacer(minLength: 4)
                VehicleTypeIcon(type: vehicle.vehicleType, size: 20)
                    .foregroundStyle(vehicle.vehicleType.rowTint)
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func thumbnail(width: CGFloat, height: CGFloat) -> some View {
        if let data = vehicle.photoData, let uiImage = ThumbnailCache.image(for: data, maxPixel: 360) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.secondary.opacity(0.15))
                .frame(width: width, height: height)
                .overlay(VehicleTypeIcon(type: vehicle.vehicleType, size: 24).foregroundStyle(.secondary))
                .accessibilityHidden(true)
        }
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
                    .overlay(VehicleTypeIcon(type: vehicle.vehicleType, size: 17).foregroundStyle(.secondary))
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
