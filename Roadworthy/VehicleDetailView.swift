import SwiftUI
import SwiftData
import PhotosUI

private enum DetailTab {
    case overview, logs
}

struct VehicleDetailView: View {
    @Bindable var vehicle: Vehicle
    @State private var selectedTab: DetailTab = .overview

    @State private var showingEditVehicle = false
    @State private var showingAddMaintenance = false
    @State private var showingAddFuel = false
    @State private var showingAddExpense = false
    @State private var showingAddReminder = false
    @State private var showingAddDocument = false
    @State private var showingAddSpec = false
    @State private var showingAddTrip = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case .overview:
                    OverviewTab(vehicle: vehicle)
                case .logs:
                    VehicleLogsView(vehicle: vehicle)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            customBottomBar
        }
        .navigationTitle(vehicle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if selectedTab == .overview {
                    Button("Edit") { showingEditVehicle = true }
                }
            }
        }
        .sheet(isPresented: $showingEditVehicle) {
            AddEditVehicleView(vehicle: vehicle)
        }
        // All "Add" sheets live here at the top level so the quick-add button
        // works no matter which screen (Overview or Vehicle Logs) is showing.
        .sheet(isPresented: $showingAddMaintenance) {
            AddEditMaintenanceView(vehicle: vehicle, record: nil)
        }
        .sheet(isPresented: $showingAddFuel) {
            AddEditFuelView(vehicle: vehicle, log: nil)
        }
        .sheet(isPresented: $showingAddExpense) {
            AddEditExpenseView(vehicle: vehicle, expense: nil)
        }
        .sheet(isPresented: $showingAddReminder) {
            AddEditReminderView(vehicle: vehicle, reminder: nil)
        }
        .sheet(isPresented: $showingAddDocument) {
            AddDocumentView(vehicle: vehicle)
        }
        .sheet(isPresented: $showingAddSpec) {
            AddEditSpecView(vehicle: vehicle, spec: nil)
        }
        .sheet(isPresented: $showingAddTrip) {
            AddEditTripView(vehicle: vehicle, trip: nil)
        }
    }

    // MARK: - Custom bottom bar

    private var customBottomBar: some View {
        HStack {
            tabBarButton(title: "Overview", systemImage: vehicle.vehicleType.iconName, tab: .overview)

            Spacer()

            quickAddMenu

            Spacer()

            tabBarButton(title: "Vehicle Logs", systemImage: "list.bullet.rectangle.fill", tab: .logs)
        }
        .padding(.horizontal, 36)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func tabBarButton(title: String, systemImage: String, tab: DetailTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
        }
    }

    // The raised center button: tap for a quick-add menu covering the five
    // entry types, without needing to open Vehicle Logs and pick a category first.
    private var quickAddMenu: some View {
        Menu {
            Button {
                showingAddSpec = true
            } label: {
                Label("Vehicle Specs", systemImage: "list.clipboard.fill")
            }
            Button {
                showingAddDocument = true
            } label: {
                Label("Document", systemImage: "doc.fill")
            }
            Button {
                showingAddReminder = true
            } label: {
                Label("Reminder", systemImage: "bell.fill")
            }
            Button {
                showingAddExpense = true
            } label: {
                Label("Expense", systemImage: "dollarsign.circle.fill")
            }
            Button {
                showingAddMaintenance = true
            } label: {
                Label("Maintenance", systemImage: "wrench.and.screwdriver.fill")
            }
            Button {
                showingAddFuel = true
            } label: {
                Label("Fuel", systemImage: "fuelpump.fill")
            }
            Button {
                showingAddTrip = true
            } label: {
                Label("Trip", systemImage: "map.fill")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .offset(y: -14)
    }
}

private struct OverviewTab: View {
    let vehicle: Vehicle

    @State private var showingInsuranceCardOptions = false
    @State private var showingInsuranceCamera = false
    @State private var showingInsurancePhotoPicker = false
    @State private var showingInsuranceCardViewer = false
    @State private var selectedInsurancePhoto: PhotosPickerItem?

    private var upcomingMaintenance: [MaintenanceRecord] {
        vehicle.maintenanceRecords
            .filter { $0.nextDueMileage != nil || $0.nextDueDate != nil }
            .sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }
    }

    private var sortedReminders: [MaintenanceReminder] {
        vehicle.reminders.sorted { lhs, rhs in
            let lhsDue = lhs.isDue(currentMileage: vehicle.currentMileage)
            let rhsDue = rhs.isDue(currentMileage: vehicle.currentMileage)
            if lhsDue != rhsDue { return lhsDue && !rhsDue }
            return (lhs.nextDueDate ?? .distantFuture) < (rhs.nextDueDate ?? .distantFuture)
        }
    }

    // MPG is calculated from the gap between consecutive full-tank fill-ups.
    private var mpgIntervals: [Double] {
        let fullTankLogs = vehicle.fuelLogs
            .filter { $0.isFullTank }
            .sorted { $0.mileage < $1.mileage }
        guard fullTankLogs.count >= 2 else { return [] }
        var intervals: [Double] = []
        for i in 1..<fullTankLogs.count {
            let milesDriven = Double(fullTankLogs[i].mileage - fullTankLogs[i - 1].mileage)
            let gallonsUsed = fullTankLogs[i].gallons
            guard gallonsUsed > 0, milesDriven > 0 else { continue }
            intervals.append(milesDriven / gallonsUsed)
        }
        return intervals
    }
    private var averageMPG: Double? {
        mpgIntervals.isEmpty ? nil : mpgIntervals.reduce(0, +) / Double(mpgIntervals.count)
    }
    private var lastMPG: Double? { mpgIntervals.last }
    private var bestMPG: Double? { mpgIntervals.max() }

    private var totalFuelCost: Double { vehicle.fuelLogs.reduce(0) { $0 + $1.totalCost } }
    private var totalGallons: Double { vehicle.fuelLogs.reduce(0) { $0 + $1.gallons } }
    private var totalMaintenanceCost: Double { vehicle.maintenanceRecords.reduce(0) { $0 + $1.cost } }
    private var totalExpenseCost: Double { vehicle.expenses.reduce(0) { $0 + $1.amount } }

    private let threeColumns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let twoColumns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photoHeader

                statSection(title: "FUEL ECONOMY") {
                    LazyVGrid(columns: threeColumns, spacing: 10) {
                        statCard(value: formattedMPG(averageMPG), label: "AVG MPG")
                        statCard(value: formattedMPG(lastMPG), label: "LAST MPG")
                        statCard(value: formattedMPG(bestMPG), label: "BEST MPG")
                    }
                }

                navSection(title: "FUEL", destination: FuelListView(vehicle: vehicle)) {
                    LazyVGrid(columns: threeColumns, spacing: 10) {
                        statCard(value: "\(vehicle.fuelLogs.count)", label: "Fuel Logs")
                        statCard(value: totalFuelCost.formatted(.currency(code: "USD").precision(.fractionLength(0))), label: "Total Cost")
                        statCard(value: totalGallons.formatted(.number.precision(.fractionLength(0))), label: "Gallons")
                    }
                }

                navSection(title: "MAINTENANCE", destination: MaintenanceListView(vehicle: vehicle)) {
                    LazyVGrid(columns: twoColumns, spacing: 10) {
                        statCard(value: "\(vehicle.maintenanceRecords.count)", label: "Service Logs")
                        statCard(value: totalMaintenanceCost.formatted(.currency(code: "USD").precision(.fractionLength(0))), label: "Total Cost")
                    }
                }

                navSection(title: "OTHER EXPENSES", destination: ExpenseListView(vehicle: vehicle)) {
                    LazyVGrid(columns: twoColumns, spacing: 10) {
                        statCard(value: "\(vehicle.expenses.count)", label: "Expense Logs")
                        statCard(value: totalExpenseCost.formatted(.currency(code: "USD").precision(.fractionLength(0))), label: "Total Cost")
                    }
                }

                if !vehicle.reminders.isEmpty {
                    statSection(title: "REMINDERS") {
                        VStack(spacing: 10) {
                            ForEach(sortedReminders) { reminder in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(reminder.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if let dueMileage = reminder.nextDueMileage {
                                            Text("Every \(reminder.intervalMiles.formatted()) mi — next at \(dueMileage.formatted()) mi")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let dueDate = reminder.nextDueDate {
                                            Text("Every \(reminder.intervalMonths) mo — next on \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if reminder.isDue(currentMileage: vehicle.currentMileage) {
                                        Text("Due")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Capsule().fill(Color.red))
                                    }
                                }
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }

                statSection(title: "VEHICLE INFO") {
                    VStack(spacing: 0) {
                        infoRow("Type", vehicle.vehicleType.rawValue)
                        Divider().padding(.leading, 12)
                        infoRow("Year/Make/Model", "\(vehicle.year) \(vehicle.make) \(vehicle.model)")
                        Divider().padding(.leading, 12)
                        infoRow("Mileage", "\(vehicle.currentMileage.formatted()) mi")
                        if !vehicle.vin.isEmpty {
                            Divider().padding(.leading, 12)
                            infoRow("VIN", vehicle.vin)
                        }
                        if !vehicle.licensePlate.isEmpty {
                            Divider().padding(.leading, 12)
                            infoRow("Plate", vehicle.licensePlate)
                        }
                        Divider().padding(.leading, 12)
                        infoRow("Purchased", vehicle.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                        Divider().padding(.leading, 12)
                        insuranceCardRow
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !upcomingMaintenance.isEmpty {
                    statSection(title: "UPCOMING / DUE") {
                        VStack(spacing: 10) {
                            ForEach(upcomingMaintenance) { record in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    if let dueDate = record.nextDueDate {
                                        Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let dueMileage = record.nextDueMileage {
                                        Text("Due at \(dueMileage.formatted()) mi")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func formattedMPG(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    @ViewBuilder
    private var photoHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = vehicle.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 200)
                    .overlay(
                        Image(systemName: vehicle.vehicleType.iconName)
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                    )
            }
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .frame(height: 200)
            Text(vehicle.displayName)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    private func statSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            content()
                .padding(.horizontal, 16)
        }
    }

    // A tappable version of statSection that pushes to a detail screen —
    // used for sections backed by a browsable list (Fuel, Maintenance, Expenses).
    private func navSection<Destination: View, Content: View>(
        title: String,
        destination: Destination,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                content()
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var insuranceCardRow: some View {
        Button {
            showingInsuranceCardOptions = true
        } label: {
            HStack {
                Text("Insurance Card").foregroundStyle(.secondary)
                Spacer()
                if let data = vehicle.insuranceCardData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("Add")
                        .foregroundStyle(.primary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .confirmationDialog("Insurance Card", isPresented: $showingInsuranceCardOptions, titleVisibility: .visible) {
            Button("Take Photo") { showingInsuranceCamera = true }
            Button("Choose from Library") { showingInsurancePhotoPicker = true }
            if vehicle.insuranceCardData != nil {
                Button("View Photo") { showingInsuranceCardViewer = true }
                Button("Remove Photo", role: .destructive) { vehicle.insuranceCardData = nil }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingInsuranceCamera) {
            CameraPicker(imageData: Binding(
                get: { vehicle.insuranceCardData },
                set: { vehicle.insuranceCardData = $0 }
            ))
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingInsurancePhotoPicker, selection: $selectedInsurancePhoto, matching: .images)
        .onChange(of: selectedInsurancePhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    vehicle.insuranceCardData = data
                }
            }
        }
        .sheet(isPresented: $showingInsuranceCardViewer) {
            if let data = vehicle.insuranceCardData, let uiImage = UIImage(data: data) {
                NavigationStack {
                    ScrollView {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                    .navigationTitle("Insurance Card")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingInsuranceCardViewer = false }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        VehicleDetailView(vehicle: Vehicle(nickname: "Test Truck", make: "Toyota", model: "Tacoma", year: 2020))
    }
    .modelContainer(for: [Vehicle.self], inMemory: true)
}
