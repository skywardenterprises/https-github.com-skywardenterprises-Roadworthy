import Foundation
import SwiftData

// MARK: - Vehicle Type

enum VehicleType: String, CaseIterable, Codable, Identifiable {
    case car = "Car"
    case motorcycle = "Motorcycle"
    case truck = "Truck"
    case rv = "RV"
    case other = "Other"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .car: return "car.fill"
        case .motorcycle: return "motorcycle.fill"
        case .truck: return "box.truck.fill"
        case .rv: return "bus.fill"
        case .other: return "car.fill"
        }
    }
}

// MARK: - Vehicle

@Model
final class Vehicle {
    var nickname: String = ""
    var make: String = ""
    var model: String = ""
    var year: Int = Calendar.current.component(.year, from: .now)
    var vin: String = ""
    var licensePlate: String = ""
    var currentMileage: Int = 0
    var purchaseDate: Date = Date.now
    var photoData: Data?
    var insuranceCardData: Data?
    var isActive: Bool = true
    var inactiveDate: Date?
    var vehicleType: VehicleType = VehicleType.car
    var purchasePrice: Double = 0
    var estimatedCurrentValue: Double?
    var estimatedValueUpdatedDate: Date?

    // CloudKit requires to-many relationships to be declared as Optional
    // arrays. Each one below is renamed with a "Storage" suffix, with a
    // plain computed property underneath (further down) providing the
    // original name as a non-optional array — so nothing elsewhere in the
    // app needs to change.
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceRecord.vehicle)
    var maintenanceRecordsStorage: [MaintenanceRecord]? = []

    @Relationship(deleteRule: .cascade, inverse: \FuelLog.vehicle)
    var fuelLogsStorage: [FuelLog]? = []

    @Relationship(deleteRule: .cascade, inverse: \ExpenseRecord.vehicle)
    var expensesStorage: [ExpenseRecord]? = []

    @Relationship(deleteRule: .cascade, inverse: \VehicleDocument.vehicle)
    var documentsStorage: [VehicleDocument]? = []

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceReminder.vehicle)
    var remindersStorage: [MaintenanceReminder]? = []

    @Relationship(deleteRule: .cascade, inverse: \VehicleSpec.vehicle)
    var specsStorage: [VehicleSpec]? = []

    @Relationship(deleteRule: .cascade, inverse: \TripLog.vehicle)
    var tripsStorage: [TripLog]? = []

    init(
        nickname: String,
        make: String,
        model: String,
        year: Int,
        vin: String = "",
        licensePlate: String = "",
        currentMileage: Int = 0,
        purchaseDate: Date = .now,
        photoData: Data? = nil,
        insuranceCardData: Data? = nil,
        isActive: Bool = true,
        inactiveDate: Date? = nil,
        vehicleType: VehicleType = .car,
        purchasePrice: Double = 0,
        estimatedCurrentValue: Double? = nil,
        estimatedValueUpdatedDate: Date? = nil
    ) {
        self.nickname = nickname
        self.make = make
        self.model = model
        self.year = year
        self.vin = vin
        self.licensePlate = licensePlate
        self.currentMileage = currentMileage
        self.purchaseDate = purchaseDate
        self.photoData = photoData
        self.insuranceCardData = insuranceCardData
        self.vehicleType = vehicleType
        self.purchasePrice = purchasePrice
        self.estimatedCurrentValue = estimatedCurrentValue
        self.estimatedValueUpdatedDate = estimatedValueUpdatedDate
        self.isActive = isActive
        self.inactiveDate = inactiveDate
    }

    var displayName: String {
        nickname.isEmpty ? "\(year) \(make) \(model)" : nickname
    }

    // Non-optional convenience accessors — every other file in the app
    // reads/writes through these exactly as before.
    var maintenanceRecords: [MaintenanceRecord] {
        get { maintenanceRecordsStorage ?? [] }
        set { maintenanceRecordsStorage = newValue }
    }
    var fuelLogs: [FuelLog] {
        get { fuelLogsStorage ?? [] }
        set { fuelLogsStorage = newValue }
    }
    var expenses: [ExpenseRecord] {
        get { expensesStorage ?? [] }
        set { expensesStorage = newValue }
    }
    var documents: [VehicleDocument] {
        get { documentsStorage ?? [] }
        set { documentsStorage = newValue }
    }
    var reminders: [MaintenanceReminder] {
        get { remindersStorage ?? [] }
        set { remindersStorage = newValue }
    }
    var specs: [VehicleSpec] {
        get { specsStorage ?? [] }
        set { specsStorage = newValue }
    }
    var trips: [TripLog] {
        get { tripsStorage ?? [] }
        set { tripsStorage = newValue }
    }

    /// Total money spent across maintenance, fuel, and misc expenses.
    var totalSpent: Double {
        let maintenanceCost = maintenanceRecords.reduce(0) { $0 + $1.cost }
        let fuelCost = fuelLogs.reduce(0) { $0 + $1.totalCost }
        let expenseCost = expenses.reduce(0) { $0 + $1.amount }
        return maintenanceCost + fuelCost + expenseCost
    }

    /// Checks whether a fuel or maintenance entry's date/mileage would be
    /// inconsistent with an already-logged entry — the odometer shouldn't
    /// read lower at a later (or same) date than it did at an earlier one.
    /// Pass the entry currently being edited (if any) so it excludes itself
    /// from the check. Returns the conflicting entry's date/mileage, if any.
    func mileageConflict(
        forDate date: Date,
        mileage: Int,
        excludingFuelLog: FuelLog? = nil,
        excludingMaintenanceRecord: MaintenanceRecord? = nil
    ) -> (date: Date, mileage: Int)? {
        var conflicts: [(date: Date, mileage: Int)] = []

        // Checks both directions: an earlier-or-same-dated entry shouldn't
        // have HIGHER mileage than this one, and a later-or-same-dated entry
        // shouldn't have LOWER mileage than this one — either way, the
        // odometer would have had to run backwards.
        func check(_ entryDate: Date, _ entryMileage: Int) {
            if entryDate <= date && entryMileage > mileage {
                conflicts.append((entryDate, entryMileage))
            } else if entryDate >= date && entryMileage < mileage {
                conflicts.append((entryDate, entryMileage))
            }
        }

        for log in fuelLogs where log !== excludingFuelLog {
            check(log.date, log.mileage)
        }
        for record in maintenanceRecords where record !== excludingMaintenanceRecord {
            check(record.date, record.mileage)
        }

        // The conflict with the biggest mileage gap is the most informative one to show.
        return conflicts.max { abs($0.mileage - mileage) < abs($1.mileage - mileage) }
    }
}

/// Builds a clear, direction-aware message for a mileage conflict — the
/// True if the given date is a future calendar day (compares just the day,
/// not the exact time, so picking "today" is never mistakenly flagged).
func isFutureDate(_ date: Date) -> Bool {
    Calendar.current.startOfDay(for: date) > Calendar.current.startOfDay(for: .now)
}

/// True if the given date falls before the vehicle's model year — a vehicle
/// can't have a fuel-up or maintenance event before it existed.
func isBeforeManufactureYear(_ date: Date, vehicleYear: Int) -> Bool {
    Calendar.current.component(.year, from: date) < vehicleYear
}

/// wording differs depending on whether the conflicting entry is dated
/// before (and has higher mileage) or after (and has lower mileage).
func buildMileageConflictMessage(newMileage: Int, newDate: Date, conflict: (date: Date, mileage: Int)) -> String {
    let conflictDate = conflict.date.formatted(date: .abbreviated, time: .omitted)
    if conflict.date <= newDate {
        return "This entry's mileage (\(newMileage.formatted()) mi) is lower than a previous log from \(conflictDate) at \(conflict.mileage.formatted()) mi. Please correct the mileage or the date before saving."
    } else {
        return "This entry's mileage (\(newMileage.formatted()) mi) is higher than a later log from \(conflictDate) at \(conflict.mileage.formatted()) mi. Please correct the mileage or the date before saving."
    }
}

// MARK: - Maintenance

enum MaintenanceType: String, CaseIterable, Codable, Identifiable {
    case oilChange = "Oil Change"
    case tireRotation = "Tire Rotation"
    case tireReplacement = "Tire Replacement"
    case brakes = "Brakes"
    case battery = "Battery"
    case fluids = "Fluids"
    case inspection = "Inspection"
    case registration = "Registration"
    case airFilter = "Air Filter"
    case chainLubrication = "Chain Lubrication"
    case chainAdjustment = "Chain Adjustment"
    case valveClearance = "Valve Clearance"
    case coolantFlush = "Coolant Flush"
    case other = "Other"

    var id: String { rawValue }

    /// Shown in pickers instead of the raw stored value — "Custom" reads
    /// more clearly than "Other" as an option someone taps to type their own.
    /// The underlying stored value stays "Other" so existing data is unaffected.
    var displayName: String {
        self == .other ? "Custom" : rawValue
    }
}

@Model
final class MaintenanceRecord {
    var type: MaintenanceType = MaintenanceType.other
    var title: String = ""
    var date: Date = Date.now
    var mileage: Int = 0
    var cost: Double = 0
    var notes: String = ""
    var nextDueMileage: Int?
    var nextDueDate: Date?
    var receiptPhotoData: Data?
    var vehicle: Vehicle?

    init(
        type: MaintenanceType,
        title: String = "",
        date: Date = .now,
        mileage: Int = 0,
        cost: Double = 0,
        notes: String = "",
        nextDueMileage: Int? = nil,
        nextDueDate: Date? = nil,
        receiptPhotoData: Data? = nil
    ) {
        self.type = type
        self.title = title.isEmpty ? type.rawValue : title
        self.date = date
        self.mileage = mileage
        self.cost = cost
        self.notes = notes
        self.nextDueMileage = nextDueMileage
        self.nextDueDate = nextDueDate
        self.receiptPhotoData = receiptPhotoData
    }
}

// MARK: - Fuel

@Model
final class FuelLog {
    var date: Date = Date.now
    var mileage: Int = 0
    var gallons: Double = 0
    var pricePerGallon: Double = 0
    var isFullTank: Bool = true
    var receiptPhotoData: Data?
    var vehicle: Vehicle?

    init(
        date: Date = .now,
        mileage: Int = 0,
        gallons: Double = 0,
        pricePerGallon: Double = 0,
        isFullTank: Bool = true,
        receiptPhotoData: Data? = nil
    ) {
        self.date = date
        self.mileage = mileage
        self.gallons = gallons
        self.pricePerGallon = pricePerGallon
        self.isFullTank = isFullTank
        self.receiptPhotoData = receiptPhotoData
    }

    var totalCost: Double { gallons * pricePerGallon }
}

// MARK: - Expenses

enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case insurance = "Insurance"
    case parking = "Parking"
    case tolls = "Tolls"
    case carWash = "Car Wash"
    case accessories = "Accessories"
    case fines = "Fines"
    case other = "Other"

    var id: String { rawValue }
}

@Model
final class ExpenseRecord {
    var category: ExpenseCategory = ExpenseCategory.other
    var date: Date = Date.now
    var amount: Double = 0
    var notes: String = ""
    var receiptPhotoData: Data?
    var vehicle: Vehicle?

    init(
        category: ExpenseCategory,
        date: Date = .now,
        amount: Double = 0,
        notes: String = "",
        receiptPhotoData: Data? = nil
    ) {
        self.category = category
        self.date = date
        self.amount = amount
        self.notes = notes
        self.receiptPhotoData = receiptPhotoData
    }
}

// MARK: - Documents (registration, insurance card, etc.)

@Model
final class VehicleDocument {
    var title: String = ""
    var dateAdded: Date = Date.now
    var imageData: Data?
    var notes: String = ""
    var vehicle: Vehicle?

    init(
        title: String,
        dateAdded: Date = .now,
        imageData: Data? = nil,
        notes: String = ""
    ) {
        self.title = title
        self.dateAdded = dateAdded
        self.imageData = imageData
        self.notes = notes
    }
}

// MARK: - Recurring Reminders

/// A recurring maintenance reminder. It can repeat by mileage, by a time
/// interval, or both — if both are set, whichever threshold is reached
/// first is what triggers the reminder as "due."
@Model
final class MaintenanceReminder {
    var title: String = ""
    var type: MaintenanceType = MaintenanceType.other
    var notes: String = ""

    var repeatByMileage: Bool = false
    var intervalMiles: Int = 0      // e.g. every 5000 miles

    var repeatByDate: Bool = false
    var intervalMonths: Int = 0     // e.g. every 6 months

    // The mileage/date this reminder was last "reset" from — either when it
    // was created, or the last time it was marked done.
    var baselineMileage: Int = 0
    var baselineDate: Date = Date.now

    // A stable ID used to schedule/cancel this reminder's local notification.
    var reminderID: UUID = UUID()
    var notificationsEnabled: Bool = false
    var notifyDaysBefore: Int = 0   // 0 = notify on the due date itself

    var vehicle: Vehicle?

    init(
        title: String,
        type: MaintenanceType = .other,
        notes: String = "",
        repeatByMileage: Bool = false,
        intervalMiles: Int = 0,
        repeatByDate: Bool = false,
        intervalMonths: Int = 0,
        baselineMileage: Int = 0,
        baselineDate: Date = .now,
        notificationsEnabled: Bool = false,
        notifyDaysBefore: Int = 0
    ) {
        self.title = title
        self.type = type
        self.notes = notes
        self.repeatByMileage = repeatByMileage
        self.intervalMiles = intervalMiles
        self.repeatByDate = repeatByDate
        self.intervalMonths = intervalMonths
        self.baselineMileage = baselineMileage
        self.baselineDate = baselineDate
        self.notificationsEnabled = notificationsEnabled
        self.notifyDaysBefore = notifyDaysBefore
    }

    var nextDueMileage: Int? {
        guard repeatByMileage, intervalMiles > 0 else { return nil }
        return baselineMileage + intervalMiles
    }

    var nextDueDate: Date? {
        guard repeatByDate, intervalMonths > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: intervalMonths, to: baselineDate)
    }

    /// The date the notification should fire on — the due date, pulled
    /// earlier by notifyDaysBefore if that's set. Nil if this reminder
    /// isn't date-based (mileage-only reminders can't be scheduled in
    /// advance, since there's no way to predict when a mileage will be hit).
    var notificationFireDate: Date? {
        guard let nextDueDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: -notifyDaysBefore, to: nextDueDate)
    }

    /// True if either the mileage threshold or the date threshold has been reached.
    func isDue(currentMileage: Int) -> Bool {
        if let nextDueMileage, currentMileage >= nextDueMileage {
            return true
        }
        if let nextDueDate, Date.now >= nextDueDate {
            return true
        }
        return false
    }

    /// Miles remaining until due — negative once past due. Nil if this
    /// reminder isn't mileage-tracked.
    func milesRemaining(currentMileage: Int) -> Int? {
        guard let nextDueMileage else { return nil }
        return nextDueMileage - currentMileage
    }

    /// Days remaining until due — negative once past due. Nil if this
    /// reminder isn't date-tracked.
    var daysRemaining: Int? {
        guard let nextDueDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date.now, to: nextDueDate).day
    }

    /// True if the reminder is coming due soon (within 2 weeks or 1,000
    /// miles) but hasn't hit its threshold yet.
    func isDueSoon(currentMileage: Int) -> Bool {
        guard !isDue(currentMileage: currentMileage) else { return false }
        if let miles = milesRemaining(currentMileage: currentMileage), miles <= 1000 { return true }
        if let days = daysRemaining, days <= 14 { return true }
        return false
    }

    /// Sort key for reminder lists: mileage-tracked reminders sort by miles
    /// remaining (soonest — or most overdue — first, since overdue values
    /// are negative and naturally sort to the front). Reminders with no
    /// mileage component sort after all mileage-tracked ones, by days
    /// remaining.
    func sortKey(currentMileage: Int) -> (Int, Int) {
        if let miles = milesRemaining(currentMileage: currentMileage) {
            return (0, miles)
        }
        return (1, daysRemaining ?? Int.max)
    }

    func status(currentMileage: Int) -> ReminderStatus {
        if isDue(currentMileage: currentMileage) { return .overdue }
        if isDueSoon(currentMileage: currentMileage) { return .upcoming }
        return .onTrack
    }
}

/// The three states a reminder can be in, used to drive the small status
/// badge shown wherever reminders appear.
enum ReminderStatus: String {
    case overdue = "Overdue"
    case upcoming = "Upcoming"
    case onTrack = "On Track"
}

// MARK: - Vehicle Specs (parts reference & torque specs)

enum SpecCategory: String, CaseIterable, Codable, Identifiable {
    case part = "Part"
    case torque = "Torque Spec"

    var id: String { rawValue }

    /// Shown in the UI instead of the raw stored value — the stored value
    /// stays "Part" so any specs already saved (including synced ones)
    /// aren't affected by the rename.
    var displayName: String {
        self == .part ? "Part Info" : rawValue
    }
}

/// A quick-reference item — either a replaceable part (with its part number)
/// or a torque spec (with its value), kept separate from the maintenance
/// history log so common lookups don't get buried in past service records.
@Model
final class VehicleSpec {
    var category: SpecCategory = SpecCategory.part
    var name: String = ""    // e.g. "Oil Filter", "Wheel Lug Nuts"
    var value: String = ""   // e.g. "PH3593A", "89 ft-lb"
    var brand: String = ""   // e.g. "Bosch", "Fram" — parts only
    var notes: String = ""
    var vehicle: Vehicle?

    init(
        category: SpecCategory,
        name: String,
        value: String = "",
        brand: String = "",
        notes: String = ""
    ) {
        self.category = category
        self.name = name
        self.value = value
        self.brand = brand
        self.notes = notes
    }
}

// MARK: - Trip Log (business mileage tracking)

enum TripPurpose: String, CaseIterable, Codable, Identifiable {
    case business = "Business"
    case personal = "Personal"
    case commuting = "Commuting"

    var id: String { rawValue }
}

/// A single logged drive, used for business mileage / tax deduction tracking.
/// Distance is derived from a start and end odometer reading, matching how
/// mileage is tracked everywhere else in the app.
@Model
final class TripLog {
    var date: Date = Date.now
    var startMileage: Int = 0
    var endMileage: Int = 0
    var purpose: TripPurpose = TripPurpose.business
    var businessPurposeNote: String = ""   // required by the IRS for business trips
    var fromLocation: String = ""
    var toLocation: String = ""
    var vehicle: Vehicle?

    init(
        date: Date = .now,
        startMileage: Int = 0,
        endMileage: Int = 0,
        purpose: TripPurpose = .business,
        businessPurposeNote: String = "",
        fromLocation: String = "",
        toLocation: String = ""
    ) {
        self.date = date
        self.startMileage = startMileage
        self.endMileage = endMileage
        self.purpose = purpose
        self.businessPurposeNote = businessPurposeNote
        self.fromLocation = fromLocation
        self.toLocation = toLocation
    }

    var milesDriven: Int {
        max(0, endMileage - startMileage)
    }
}
