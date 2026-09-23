import SwiftUI
import SwiftData
import PhotosUI

private enum DetailTab {
    case overview, logs
}

/// Every sheet this screen can show. One `sheet(item:)` driven by this enum
/// replaces eight separate `sheet(isPresented:)` modifiers, matching how the
/// list screens present their edit forms.
private enum DetailSheet: String, Identifiable {
    case editVehicle, maintenance, fuel, expense, reminder, document, spec, trip
    var id: String { rawValue }
}

struct VehicleDetailView: View {
    let vehicle: Vehicle
    @State private var selectedTab: DetailTab = .overview

    @State private var activeSheet: DetailSheet?

    var body: some View {
        // A vehicle deleted on another device can disappear while this screen
        // is showing it. Reading a deleted SwiftData object's properties can
        // crash, so check first and show a placeholder instead.
        if vehicle.isDeleted || vehicle.modelContext == nil {
            ContentUnavailableView(
                "Vehicle Deleted",
                systemImage: "car.fill",
                description: Text("This vehicle was deleted, possibly on another device.")
            )
        } else {
            content
        }
    }

    private var content: some View {
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
                    Button("Edit") { activeSheet = .editVehicle }
                }
            }
        }
        // All sheets live here at the top level so the quick-add button
        // works no matter which screen (Overview or Vehicle Logs) is showing.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editVehicle:
                AddEditVehicleView(vehicle: vehicle)
            case .maintenance:
                AddEditMaintenanceView(vehicle: vehicle, record: nil)
            case .fuel:
                AddEditFuelView(vehicle: vehicle, log: nil)
            case .expense:
                AddEditExpenseView(vehicle: vehicle, expense: nil)
            case .reminder:
                AddEditReminderView(vehicle: vehicle, reminder: nil)
            case .document:
                AddEditDocumentView(vehicle: vehicle)
            case .spec:
                AddEditSpecView(vehicle: vehicle, spec: nil)
            case .trip:
                AddEditTripView(vehicle: vehicle, trip: nil)
            }
        }
    }

    // MARK: - Custom bottom bar

    private var customBottomBar: some View {
        HStack {
            tabBarButton(title: "Overview", systemImage: vehicle.vehicleType.iconName, tab: .overview)
                .frame(maxWidth: .infinity)

            quickAddMenu

            tabBarButton(title: "Vehicle Logs", systemImage: "list.bullet.rectangle.fill", tab: .logs)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
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

    // The raised center button: tap for a quick-add menu covering all seven
    // entry types, without needing to open Vehicle Logs and pick a category first.
    private var quickAddMenu: some View {
        Menu {
            Button {
                activeSheet = .spec
            } label: {
                Label("Vehicle Specs", systemImage: "list.clipboard.fill")
            }
            Button {
                activeSheet = .document
            } label: {
                Label("Document", systemImage: "doc.fill")
            }
            Button {
                activeSheet = .reminder
            } label: {
                Label("Reminder", systemImage: "bell.fill")
            }
            Button {
                activeSheet = .expense
            } label: {
                Label("Expense", systemImage: "dollarsign.circle.fill")
            }
            Button {
                activeSheet = .maintenance
            } label: {
                Label("Maintenance", systemImage: "wrench.and.screwdriver.fill")
            }
            Button {
                activeSheet = .fuel
            } label: {
                Label("Fuel", systemImage: "fuelpump.fill")
            }
            Button {
                activeSheet = .trip
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
        .accessibilityLabel("Quick Add")
        .accessibilityHint("Opens a menu to add fuel, maintenance, an expense, a reminder, a document, a spec, or a trip")
    }
}

private struct OverviewTab: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles

    @State private var isShowingFullPhoto = false

    @State private var showingInsuranceCardOptions = false
    @State private var showingInsuranceCamera = false
    @State private var showingInsurancePhotoPicker = false
    @State private var showingInsuranceCardViewer = false
    @State private var selectedInsurancePhoto: PhotosPickerItem?
    @State private var isLoadingInsurancePhoto = false
    @State private var showingRemoveInsuranceConfirm = false
    @State private var saveError: String?

    /// The next-due entry from the most recent service of each kind. An
    /// older record's next-due date was replaced as soon as that service
    /// was done again, so it no longer belongs in the list. Custom (Other)
    /// services are grouped by their title.
    private var upcomingMaintenance: [MaintenanceRecord] {
        let byKind = Dictionary(grouping: vehicle.maintenanceRecords) { record in
            record.type == .other ? "other:" + record.title.lowercased() : record.type.rawValue
        }
        return byKind.values
            .compactMap { records in records.max { $0.date < $1.date } }
            .filter { ($0.nextDueMileage ?? 0) > 0 || $0.nextDueDate != nil }
            .sorted { ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture) }
    }

    private func isOverdue(_ record: MaintenanceRecord) -> Bool {
        if let dueDate = record.nextDueDate,
           Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: .now) {
            return true
        }
        if let dueMileage = record.nextDueMileage, dueMileage > 0, vehicle.currentMileage >= dueMileage {
            return true
        }
        return false
    }

    private var sortedReminders: [MaintenanceReminder] {
        vehicle.reminders.sorted {
            $0.sortKey(currentMileage: vehicle.currentMileage) < $1.sortKey(currentMileage: vehicle.currentMileage)
        }
    }

    // Excludes implausible intervals (a typo, a missed fill-up, etc.) so one
    // bad data point can't silently distort Average/Last/Best MPG.
    private var mpgIntervals: [Double] {
        MPGCalculator.plausibleIntervals(for: vehicle.fuelLogs).map(\.mpg)
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
        ZStack {
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
                            statCard(value: totalFuelCost.formatted(.currency(code: AppCurrency.code).precision(.fractionLength(0))), label: "Total Cost")
                            statCard(value: totalGallons.formatted(.number.precision(.fractionLength(0))), label: "Gallons")
                        }
                    }

                    navSection(title: "MAINTENANCE", destination: MaintenanceListView(vehicle: vehicle)) {
                        LazyVGrid(columns: twoColumns, spacing: 10) {
                            statCard(value: "\(vehicle.maintenanceRecords.count)", label: "Service Logs")
                            statCard(value: totalMaintenanceCost.formatted(.currency(code: AppCurrency.code).precision(.fractionLength(0))), label: "Total Cost")
                        }
                    }

                    navSection(title: "OTHER EXPENSES", destination: ExpenseListView(vehicle: vehicle)) {
                        LazyVGrid(columns: twoColumns, spacing: 10) {
                            statCard(value: "\(vehicle.expenses.count)", label: "Expense Logs")
                            statCard(value: totalExpenseCost.formatted(.currency(code: AppCurrency.code).precision(.fractionLength(0))), label: "Total Cost")
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
                                                Text("Every \(convertFromMiles(reminder.intervalMiles, to: distanceUnit).formatted()) \(distanceUnit.rawValue) — next at \(Text(formattedDistance(dueMileage, unit: distanceUnit)).foregroundStyle(reminder.mileageTint(currentMileage: vehicle.currentMileage)))")
                                                    .foregroundStyle(.secondary)
                                                    .font(.caption)
                                            }
                                            if let dueDate = reminder.nextDueDate {
                                                Text("Every \(reminder.intervalMonths) mo — next on \(Text(dueDate.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(reminder.dateTint(currentMileage: vehicle.currentMileage)))")
                                                    .foregroundStyle(.secondary)
                                                    .font(.caption)
                                            }
                                        }
                                        Spacer()
                                        ReminderStatusBadge(status: reminder.status(currentMileage: vehicle.currentMileage))
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
                            infoRow("Odometer", formattedDistance(vehicle.currentMileage, unit: distanceUnit))
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
                                                .foregroundStyle(isOverdue(record) ? .red : .secondary)
                                        }
                                        if let dueMileage = record.nextDueMileage, dueMileage > 0 {
                                            Text("Due at \(formattedDistance(dueMileage, unit: distanceUnit))")
                                                .font(.caption)
                                                .foregroundStyle(isOverdue(record) ? .red : .secondary)
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

            if isShowingFullPhoto, let data = vehicle.photoData, let uiImage = ThumbnailCache.image(for: data, maxPixel: 2400) {
                Color.black
                    .ignoresSafeArea()
                    .transition(.opacity)
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .transition(.opacity)
            }
        }
    }

    private func formattedMPG(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    @ViewBuilder
    private var photoHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = vehicle.photoData, let uiImage = ThumbnailCache.image(for: data, maxPixel: 1400) {
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
        .onLongPressGesture(minimumDuration: 0.2, maximumDistance: 50) {
            // no-op: the "pressing" closure below does all the work
        } onPressingChanged: { pressing in
            guard vehicle.photoData != nil else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isShowingFullPhoto = pressing
            }
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
                        .accessibilityHidden(true)
                }
                content()
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full \(title.lowercased()) list")
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

    /// Writes the insurance card photo and saves right away, reporting a
    /// failure instead of relying on autosave.
    private var insuranceCardBinding: Binding<Data?> {
        Binding(
            get: { vehicle.insuranceCardData },
            set: { setInsuranceCard($0) }
        )
    }

    private func setInsuranceCard(_ data: Data?) {
        vehicle.insuranceCardData = data
        if let message = context.saveReportingErrors() {
            saveError = message
        }
    }

    private var insuranceCardRow: some View {
        Button {
            showingInsuranceCardOptions = true
        } label: {
            HStack {
                Text("Insurance Card").foregroundStyle(.secondary)
                Spacer()
                if isLoadingInsurancePhoto {
                    ProgressView()
                } else if let data = vehicle.insuranceCardData, let uiImage = ThumbnailCache.image(for: data, maxPixel: 132) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityHidden(true)
                } else {
                    Text("Add")
                        .foregroundStyle(.primary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vehicle.insuranceCardData != nil ? "Insurance Card, added" : "Insurance Card, not added")
        .accessibilityHint("Opens options to take or choose a photo")
        .confirmationDialog("Insurance Card", isPresented: $showingInsuranceCardOptions, titleVisibility: .visible) {
            if CameraPicker.isAvailable {
                Button("Take Photo") { showingInsuranceCamera = true }
            }
            Button("Choose from Library") { showingInsurancePhotoPicker = true }
            if vehicle.insuranceCardData != nil {
                Button("View Photo") { showingInsuranceCardViewer = true }
                Button("Remove Photo", role: .destructive) { showingRemoveInsuranceConfirm = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingInsuranceCamera) {
            CameraPicker(imageData: insuranceCardBinding)
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingInsurancePhotoPicker, selection: $selectedInsurancePhoto, matching: .images)
        // Same loader as every other photo field: normalized size, the same
        // photo can be picked again, and a failed load shows an alert.
        .loadsPickedPhoto($selectedInsurancePhoto, into: insuranceCardBinding, isLoading: $isLoadingInsurancePhoto)
        .deleteConfirmation("Remove the insurance card photo?", isPresented: $showingRemoveInsuranceConfirm) {
            setInsuranceCard(nil)
        }
        .saveErrorAlert($saveError)
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
