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
                    subtitle: L("%lld logged", vehicle.maintenanceRecords.count)
                )
            }

            NavigationLink {
                FuelListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "fuelpump.fill",
                    title: "Fuel",
                    subtitle: L("%lld logged", vehicle.fuelLogs.count)
                )
            }

            NavigationLink {
                ExpenseListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "dollarsign.circle.fill",
                    title: "Expenses",
                    subtitle: L("%lld logged", vehicle.expenses.count)
                )
            }

            NavigationLink {
                TripListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "map.fill",
                    title: "Trips",
                    subtitle: L("%lld logged", vehicle.trips.count)
                )
            }

            NavigationLink {
                ReminderListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "bell.fill",
                    title: "Reminders",
                    subtitle: L("%lld set", vehicle.reminders.count)
                )
            }

            NavigationLink {
                DocumentListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "doc.fill",
                    title: "Documents",
                    subtitle: L("%lld saved", vehicle.documents.count)
                )
            }

            NavigationLink {
                SpecListView(vehicle: vehicle)
            } label: {
                logRow(
                    icon: "list.clipboard.fill",
                    title: "Vehicle Specs",
                    subtitle: L("%lld saved", vehicle.specs.count)
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
                Text(LocalizedStringKey(title)).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
