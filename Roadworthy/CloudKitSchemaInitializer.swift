#if DEBUG
import Foundation
import CoreData
import SwiftData
import OSLog

/// Pushes the complete Roadworthy schema to the CloudKit Development
/// environment: every record type and every field, including ones no test
/// record has ever used.
///
/// Why: CloudKit only creates a record type or field in Development the
/// first time a record with a value for it syncs. Anything missing when the
/// schema is deployed to Production doesn't exist there, and Production
/// can't create it on the fly, so the first user to save that kind of record
/// (or fill in that field) gets a sync error. This removes the guesswork.
///
/// How to run (once, after resetting Development, before deploying):
///   Product > Scheme > Edit Scheme > Run > Arguments, add
///   `-InitializeCloudKitSchema`, run the app once, then remove the argument.
///
/// Debug-only: compiled out of TestFlight and App Store builds.
enum CloudKitSchemaInitializer {
    static let launchArgument = "-InitializeCloudKitSchema"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Follows Apple's documented approach for SwiftData apps: build the
    /// equivalent Core Data model, load it in an NSPersistentCloudKitContainer
    /// pointed at the same store file, call initializeCloudKitSchema(), then
    /// release the store so SwiftData can open it normally.
    static func run(modelTypes: [any PersistentModel.Type]) {
        let log = Logger.sync
        log.notice("Initializing CloudKit Development schema…")
        do {
            try autoreleasepool {
                let storeURL = ModelConfiguration().url
                let description = NSPersistentStoreDescription(url: storeURL)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: CloudKitConfig.containerID
                )
                description.shouldAddStoreAsynchronously = false

                guard let model = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes) else {
                    log.error("Schema init: couldn't build a Core Data model from the SwiftData types.")
                    return
                }
                let container = NSPersistentCloudKitContainer(name: "Roadworthy", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]

                var loadError: Error?
                container.loadPersistentStores { _, error in loadError = error }
                if let loadError { throw loadError }

                try container.initializeCloudKitSchema()

                if let store = container.persistentStoreCoordinator.persistentStores.first {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
            log.notice("CloudKit Development schema initialized. Check Record Types in CloudKit Console, then remove the launch argument.")
        } catch {
            // Loud on purpose: this only runs when explicitly requested.
            fatalError("CloudKit schema initialization failed: \(error)")
        }
    }
}
#endif
