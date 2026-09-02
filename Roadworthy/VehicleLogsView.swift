import SwiftUI
import SwiftData

struct VehicleLogsView: View {
    let vehicle: Vehicle

    var body: some View {
        List {
            NavigationLink {
                ReportsView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Reports",
                    subtitle: "MPG, cost, and spending trends"
                )
            }

            NavigationLink {
                MaintenanceListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "wrench.and.screwdriver.fill",
                    title: "Maintenance",
                    subtitle: "\(vehicle.maintenanceRecords.count) logged"
                )
            }

            NavigationLink {
                FuelListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "fuelpump.fill",
                    title: "Fuel",
                    subtitle: "\(vehicle.fuelLogs.count) logged"
                )
            }

            NavigationLink {
                ExpenseListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "dollarsign.circle.fill",
                    title: "Expenses",
                    subtitle: "\(vehicle.expenses.count) logged"
                )
            }

            NavigationLink {
                TripListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "map.fill",
                    title: "Trips",
                    subtitle: "\(vehicle.trips.count) logged"
                )
            }

            NavigationLink {
                ReminderListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "bell.fill",
                    title: "Reminders",
                    subtitle: "\(vehicle.reminders.count) set"
                )
            }

            NavigationLink {
                DocumentListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "doc.fill",
                    title: "Documents",
                    subtitle: "\(vehicle.documents.count) saved"
                )
            }

            NavigationLink {
                SpecListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "list.clipboard.fill",
                    title: "Vehicle Specs",
                    subtitle: "\(vehicle.specs.count) saved"
                )
            }

            NavigationLink {
                ExportView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "square.and.arrow.up",
                    title: "Export & Share",
                    subtitle: "PDF, CSV, and full history report"
                )
            }
        }
        .navigationTitle("Vehicle Logs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func logRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
