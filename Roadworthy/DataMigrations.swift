import Foundation
import SwiftData
import OSLog

/// One-time data fixes that run at every launch. Each step only fetches
/// records that still need it, so once everything has been filled in the
/// fetches come back empty and the whole pass costs almost nothing.
///
/// Current steps:
/// - Copy each enum value from its legacy storage into the new raw-string
///   property (see the `...Raw` properties in Models.swift).
/// - Give every record a `stableID`.
///
/// Records that sync in later from another device are covered on the next
/// launch. Once every device has run this version, the legacy enum
/// properties can be removed from Models.swift in a later release.
enum DataMigrations {
    static func run(in context: ModelContext) {
        do {
            var updated = 0

            updated += try fill(#Predicate<Vehicle> { $0.stableID == nil || $0.vehicleTypeRaw == "" }, in: context) { vehicle in
                if vehicle.stableID == nil { vehicle.stableID = UUID() }
                if vehicle.vehicleTypeRaw.isEmpty { vehicle.vehicleTypeRaw = (vehicle.legacyVehicleType ?? .car).rawValue }
            }
            updated += try fill(#Predicate<MaintenanceRecord> { $0.stableID == nil || $0.typeRaw == "" }, in: context) { record in
                if record.stableID == nil { record.stableID = UUID() }
                if record.typeRaw.isEmpty { record.typeRaw = (record.legacyType ?? .other).rawValue }
            }
            updated += try fill(#Predicate<FuelLog> { $0.stableID == nil || $0.fuelGradeRaw == "" || $0.paymentMethodRaw == "" }, in: context) { log in
                if log.stableID == nil { log.stableID = UUID() }
                if log.fuelGradeRaw.isEmpty { log.fuelGradeRaw = (log.legacyFuelGrade ?? .regular).rawValue }
                if log.paymentMethodRaw.isEmpty { log.paymentMethodRaw = (log.legacyPaymentMethod ?? .creditCard).rawValue }
            }
            updated += try fill(#Predicate<ExpenseRecord> { $0.stableID == nil || $0.categoryRaw == "" }, in: context) { expense in
                if expense.stableID == nil { expense.stableID = UUID() }
                if expense.categoryRaw.isEmpty { expense.categoryRaw = (expense.legacyCategory ?? .other).rawValue }
            }
            updated += try fill(#Predicate<VehicleDocument> { $0.stableID == nil }, in: context) { document in
                document.stableID = UUID()
            }
            updated += try fill(#Predicate<MaintenanceReminder> { $0.stableID == nil || $0.typeRaw == "" }, in: context) { reminder in
                if reminder.stableID == nil { reminder.stableID = UUID() }
                if reminder.typeRaw.isEmpty { reminder.typeRaw = (reminder.legacyType ?? .other).rawValue }
            }
            updated += try fill(#Predicate<VehicleSpec> { $0.stableID == nil || $0.categoryRaw == "" }, in: context) { spec in
                if spec.stableID == nil { spec.stableID = UUID() }
                if spec.categoryRaw.isEmpty { spec.categoryRaw = (spec.legacyCategory ?? .part).rawValue }
            }
            updated += try fill(#Predicate<TripLog> { $0.stableID == nil || $0.purposeRaw == "" }, in: context) { trip in
                if trip.stableID == nil { trip.stableID = UUID() }
                if trip.purposeRaw.isEmpty { trip.purposeRaw = (trip.legacyPurpose ?? .business).rawValue }
            }

            if updated > 0 {
                try context.save()
                Logger.sync.notice("DataMigrations updated \(updated, privacy: .public) records.")
            }
        } catch {
            // Nothing is lost if this fails: every property reads correctly
            // from its legacy value until the fill succeeds on a later launch.
            context.rollback()
            Logger.sync.error("DataMigrations failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func fill<Model: PersistentModel>(
        _ predicate: Predicate<Model>,
        in context: ModelContext,
        update: (Model) -> Void
    ) throws -> Int {
        let models = try context.fetch(FetchDescriptor<Model>(predicate: predicate))
        models.forEach(update)
        return models.count
    }
}
