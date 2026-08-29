import SwiftUI
import SwiftData

struct VehicleListView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Vehicle> { $0.isActive == true }, sort: \Vehicle.nickname)
    private var vehicles: [Vehicle]
    @Query(filter: #Predicate<Vehicle> { $0.isActive == false }, sort: \Vehicle.nickname)
    private var inactiveVehicles: [Vehicle]
    @State private var showingAddVehicle = false

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
                .onDelete(perform: deleteVehicles)

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
                        "No Vehicles Yet",
                        systemImage: "car.fill",
                        description: Text("Tap + to add your first vehicle.")
                    )
                }
            }
            .navigationTitle("Roadworthy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddVehicle = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddVehicle) {
                AddEditVehicleView(vehicle: nil)
            }
        }
    }

    private func deleteVehicles(at offsets: IndexSet) {
        for index in offsets {
            context.delete(vehicles[index])
        }
    }
}

struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        HStack(spacing: 12) {
            if let data = vehicle.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.secondary.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .overlay(Image(systemName: vehicle.vehicleType.iconName).foregroundStyle(.secondary))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.displayName)
                    .font(.headline)
                Text(String(vehicle.year) + " " + vehicle.make + " " + vehicle.model)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(vehicle.currentMileage.formatted()) mi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VehicleListView()
        .modelContainer(for: [Vehicle.self], inMemory: true)
}
