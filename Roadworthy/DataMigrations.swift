import Foundation
import SwiftData
import OSLog

/// Data fixes that run at every launch. Each step only fetches records that
/// still need it, so normally the fetches come back empty and the pass costs
/// almost nothing.
///
/// Current step: give any record without a `stableID` its own ID. Every
/// record created by this version gets one when it's created, so this is a
/// safety net for records that arrive without one, such as a record synced
/// from a device still running a pre-release build.
enum DataMigrations {
    static func run(in context: ModelContext) {
        do {
            var updated = 0
            updated += try assignStableIDs(#Predicate<Vehicle> { $0.stableID == nil }, in: context) { $0.stableID = UUID() }
            updated += try assignStableIDs(#Predicate<MaintenanceRecord> { $0.stableID == nil }, in: context) { $0.stableID = UUID() }
            updated += try assignStableIDs(#Predicate<FuelLog> { $0.stableID == nil }, in: context) { $0.stableID = UUID() }
            updated += try assignStableIDs(#Predicate<ExpenseRecord> { $0.stableID == nil }, in: context) { $0.stableID = UUID() }
            updated += try assignStableIDs(#Predicate<VehicleDocument> { $0.stableID == nil }, in: context) { $0.stableID = UUID() }
            updated += try assignStableIDs(#Predicate<MaintenanceReminder> { $0.stableID == nil }, in: context) { $0.stableID = UUID() }
            updated += try assignStableIDs(#Predicate<VehicleSpec> { $0.stableID == nil }, in: context) { $0.stableID = UUID() }
            updated += try assignStableIDs(#Predicate<TripLog> { $0.stableID == nil }, in: context) { $0.stableID = UUID() }

            if updated > 0 {
                try context.save()
                Logger.sync.notice("DataMigrations assigned stable IDs to \(updated, privacy: .public) records.")
            }
        } catch {
            // Nothing breaks if this fails; it simply tries again next launch.
            context.rollback()
            Logger.sync.error("DataMigrations failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func assignStableIDs<Model: PersistentModel>(
        _ predicate: Predicate<Model>,
        in context: ModelContext,
        assign: (Model) -> Void
    ) throws -> Int {
        let models = try context.fetch(FetchDescriptor<Model>(predicate: predicate))
        models.forEach(assign)
        return models.count
    }
}
