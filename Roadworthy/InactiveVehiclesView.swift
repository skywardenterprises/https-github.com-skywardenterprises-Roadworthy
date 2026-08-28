import SwiftUI
import SwiftData

struct InactiveVehiclesView: View {
    @Query(filter: #Predicate<Vehicle> { $0.isActive == false }, sort: \Vehicle.nickname)
    private var vehicles: [Vehicle]

    var body: some View {
        List {
            ForEach(vehicles) { vehicle in
                NavigationLink {
                    VehicleDetailView(vehicle: vehicle)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        VehicleRow(vehicle: vehicle)
                        if let inactiveDate = vehicle.inactiveDate {
                            Text("Marked inactive \(inactiveDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Inactive Vehicles")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if vehicles.isEmpty {
                ContentUnavailableView(
                    "No Inactive Vehicles",
                    systemImage: "archivebox",
                    description: Text("Vehicles you mark as sold or inactive will appear here, with their full history kept intact.")
                )
            }
        }
    }
}
