import Foundation
import Combine
import CoreData
import CloudKit

enum CloudSyncState {
    /// iCloud isn't signed in, or is restricted — sync can't happen at all,
    /// regardless of anything else. This is distinct from a sync error.
    case unavailable(reason: String)
    case syncing
    case synced(Date)
    case error(String)
    /// No sync event has happened yet and account status is still being
    /// checked — the brief state right after launch.
    case unknown
}

/// Tracks whether iCloud sync is actually working, by listening for the
/// sync events Core Data's CloudKit integration broadcasts under the hood
/// (SwiftData is built on the same engine, but doesn't expose this status
/// directly itself).
@MainActor
final class CloudSyncMonitor: ObservableObject {
    @Published private(set) var state: CloudSyncState = .unknown

    private var lastSyncTimestamp: Double {
        get { UserDefaults.standard.double(forKey: "lastSuccessfulSyncTimestamp") }
        set { UserDefaults.standard.set(newValue, forKey: "lastSuccessfulSyncTimestamp") }
    }

    private var observerToken: NSObjectProtocol?

    init() {
        if lastSyncTimestamp > 0 {
            state = .synced(Date(timeIntervalSince1970: lastSyncTimestamp))
        }
        checkAccountStatus()
        observeEvents()
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    private func checkAccountStatus() {
        Task { @MainActor [weak self] in
            let status = try? await CKContainer.default().accountStatus()
            guard let self else { return }
            switch status {
            case .available:
                // Leave whatever state we already have — sync events
                // (or the persisted last-sync time) will reflect reality.
                break
            case .noAccount:
                self.state = .unavailable(reason: "Not signed into iCloud on this device")
            case .restricted:
                self.state = .unavailable(reason: "iCloud access is restricted on this device")
            case .couldNotDetermine, .temporarilyUnavailable, .none:
                self.state = .unavailable(reason: "Couldn't check iCloud status right now")
            @unknown default:
                self.state = .unavailable(reason: "Couldn't check iCloud status right now")
            }
        }
    }

    private func observeEvents() {
        observerToken = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else { return }

            Task { @MainActor [weak self] in
                guard let self else { return }
                if event.endDate == nil {
                    self.state = .syncing
                } else if let error = event.error {
                    self.state = .error(self.friendlyMessage(for: error))
                } else if event.succeeded {
                    let now = Date()
                    self.lastSyncTimestamp = now.timeIntervalSince1970
                    self.state = .synced(now)
                }
            }
        }
    }

    /// Translates CloudKit's raw error codes into plain language, instead
    /// of showing something like "CKErrorDomain error 2" — which is
    /// technically accurate and useless to anyone but a developer.
    private func friendlyMessage(for error: Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }

        switch ckError.code {
        case .partialFailure:
            // Some records in a batch synced, some didn't — common right
            // after a large import, and usually resolves on the next
            // automatic retry rather than needing anything from the person.
            return "Some changes are still syncing — this usually resolves on its own shortly."
        case .networkUnavailable, .networkFailure:
            return "No internet connection right now. Sync will resume automatically once you're back online."
        case .notAuthenticated:
            return "You're no longer signed into iCloud on this device."
        case .quotaExceeded:
            return "Your iCloud storage is full. Free up space to keep syncing."
        case .zoneBusy, .serviceUnavailable, .requestRateLimited:
            return "iCloud is temporarily busy. This should resolve on its own shortly."
        case .accountTemporarilyUnavailable:
            return "Your iCloud account is temporarily unavailable."
        default:
            return ckError.localizedDescription
        }
    }
}
