import Foundation
import Combine
import CoreData
import CloudKit
import OSLog

// MARK: - Shared configuration

enum CloudKitConfig {
    /// The one place the container name lives. The model container and the
    /// account check must use the same container. This name doesn't follow
    /// the "iCloud." + bundle ID pattern, so `CKContainer.default()` can't be
    /// relied on to find it.
    static let containerID = "iCloud.com.Jeremy.Roadworthy"
}

extension Logger {
    static let sync = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Roadworthy", category: "sync")
}

/// How the data store was opened at launch. Decided once in
/// `RoadworthyApp` and passed to the monitor, so the UI can never claim
/// "Synced" while running on local-only storage.
enum StoreMode: Equatable {
    /// Normal: CloudKit-backed store.
    case cloudKit
    /// The CloudKit store failed to load, so the app is running on the same
    /// data file without sync. `since` is the first launch this happened.
    case localOnly(code: String, since: Date)
    /// Neither store could be opened. The app shows a recovery screen and
    /// leaves the data file untouched.
    case failed(code: String)

    /// Short, support-friendly error code such as "CD-134060" or "CK-15".
    static func code(for error: Error) -> String {
        let nsError = error as NSError
        let domain: String
        switch nsError.domain {
        case NSCocoaErrorDomain: domain = "CD"
        case CKError.errorDomain: domain = "CK"
        default: domain = nsError.domain
        }
        return "\(domain)-\(nsError.code)"
    }
}

// MARK: - Sync state

enum CloudSyncState: Equatable {
    /// Account status is still being checked and no sync event has happened.
    case unknown
    /// iCloud isn't signed in or is restricted on this device. This is a
    /// device setting, not a sync error.
    case unavailable(reason: String)
    /// The CloudKit store failed to load. Nothing on this device is syncing.
    case localOnly(since: Date, code: String)
    case syncing
    case synced(Date)
    /// A temporary problem (network, iCloud busy). Retries automatically.
    case waitingToRetry(String)
    /// The person has to do something (free storage, sign in, update the app).
    case needsAction(String)
    /// A problem that won't fix itself and isn't the person's fault.
    case error(String)
}

extension CloudSyncState {
    var title: String {
        switch self {
        case .unknown: return "Checking Sync Status…"
        case .unavailable: return "iCloud Sync Unavailable"
        case .localOnly: return "iCloud Sync Is Off"
        case .syncing: return "Syncing…"
        case .synced: return "Synced"
        case .waitingToRetry: return "Waiting to Sync"
        case .needsAction: return "Sync Needs Attention"
        case .error: return "Sync Problem"
        }
    }

    var subtitle: String? {
        switch self {
        case .unknown, .syncing:
            return nil
        case .unavailable(let message), .waitingToRetry(let message), .needsAction(let message), .error(let message):
            return message
        case .localOnly(let since, let code):
            return "Saved on this device only since \(since.formatted(date: .abbreviated, time: .omitted)). Code \(code)."
        case .synced(let date):
            return "Last synced \(date.formatted(.relative(presentation: .named)))"
        }
    }

    /// nil means show a progress spinner instead of an icon.
    var systemImage: String? {
        switch self {
        case .unknown: return "icloud"
        case .unavailable, .localOnly: return "icloud.slash"
        case .syncing: return nil
        case .synced: return "checkmark.icloud.fill"
        case .waitingToRetry: return "arrow.clockwise.icloud"
        case .needsAction, .error: return "exclamationmark.icloud.fill"
        }
    }

    var needsAttention: Bool {
        switch self {
        case .unavailable, .localOnly, .needsAction, .error: return true
        case .unknown, .syncing, .synced, .waitingToRetry: return false
        }
    }

    var footer: String {
        switch self {
        case .unavailable:
            return "Open the Settings app, tap your name at the top, then iCloud, to sign in."
        case .localOnly:
            return "Roadworthy couldn't connect to its iCloud storage, so changes on this device aren't syncing. Don't delete the app until this is resolved. Anything added since then exists only on this device."
        default:
            return "Your data syncs automatically across your devices via iCloud. This can't be triggered manually. It happens on its own in the background."
        }
    }

    /// Shown on the main screen, not just in Settings. Only for states where
    /// data is at risk or the person has to act. Being signed out of iCloud
    /// is a choice some people make deliberately, so it isn't nagged about.
    var bannerMessage: String? {
        switch self {
        case .localOnly(_, let code):
            return "iCloud sync is off on this device. Your data is saved here only, so don't delete the app. Update Roadworthy or contact support (code \(code))."
        case .needsAction(let message), .error(let message):
            return message
        default:
            return nil
        }
    }
}

// MARK: - Monitor

/// Tracks whether iCloud sync is actually working by listening for the
/// events Core Data's CloudKit integration broadcasts. SwiftData uses the
/// same engine but doesn't expose sync status directly.
@MainActor
final class CloudSyncMonitor: ObservableObject {
    @Published private(set) var state: CloudSyncState = .unknown
    /// True once this device has finished its first download from iCloud
    /// for the current account. Until then, an empty vehicle list may just
    /// mean the data hasn't arrived yet.
    @Published private(set) var hasCompletedInitialImport: Bool
    /// nil until the account check finishes, or if it couldn't be completed.
    @Published private(set) var accountAvailable: Bool?
    /// Set when the signed-in Apple ID changed or signed out since the last
    /// run. Records from the previous account won't appear under the new one.
    @Published private(set) var accountChangedNotice = false

    let storeMode: StoreMode

    private enum Keys {
        static let lastSync = "lastSuccessfulSyncTimestamp"
        static let initialImportDone = "hasCompletedInitialCloudImport"
        static let lastUserRecordName = "lastKnownICloudUserRecordName"
    }

    private let defaults = UserDefaults.standard
    private let container = CKContainer(identifier: CloudKitConfig.containerID)

    private typealias EventType = NSPersistentCloudKitContainer.EventType
    private typealias Event = NSPersistentCloudKitContainer.Event

    /// Latest finished event of each type (setup, import, export), tracked
    /// separately so a download success can't hide an upload failure.
    private var latestByType: [EventType: Event] = [:]
    /// Events that have started but not finished, with their start time.
    private var inProgress: [UUID: Date] = [:]
    /// Consecutive failures per event type, used to escalate errors that
    /// aren't recognized.
    private var failureStreak: [EventType: Int] = [:]
    /// An account-level problem outranks any sync event state.
    private var accountIssue: CloudSyncState?

    /// Requires Swift 5.10 / Xcode 15.3+. Lets `deinit`, which isn't isolated
    /// to the main actor, remove the observers.
    nonisolated(unsafe) private var observerTokens: [NSObjectProtocol] = []

    init(storeMode: StoreMode = .cloudKit) {
        self.storeMode = storeMode
        self.hasCompletedInitialImport = UserDefaults.standard.bool(forKey: Keys.initialImportDone)

        switch storeMode {
        case .localOnly(let code, let since):
            // Nothing will sync, and no events will arrive. Say so plainly
            // instead of showing a stale "Synced" timestamp.
            state = .localOnly(since: since, code: code)
            return
        case .failed:
            // RootView shows the recovery screen. There's nothing to monitor.
            return
        case .cloudKit:
            break
        }

        let last = defaults.double(forKey: Keys.lastSync)
        if last > 0 {
            state = .synced(Date(timeIntervalSince1970: last))
        }
        observeEvents()
        observeAccountChanges()
        Task { await refreshAccountStatus() }
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: Derived flags for the UI

    /// True while this device has iCloud but hasn't finished its first
    /// download. Use it to show "Checking iCloud for your vehicles…" on an
    /// empty list and to warn before importing a file.
    var isWaitingForInitialImport: Bool {
        guard case .cloudKit = storeMode, accountAvailable == true else { return false }
        return !hasCompletedInitialImport
    }

    /// Whether it's safe to offer the first-run import prompt without risking
    /// duplicates of data that's still downloading.
    var canOfferImport: Bool {
        switch storeMode {
        case .localOnly, .failed:
            return true
        case .cloudKit:
            guard let accountAvailable else { return false } // still checking
            return !accountAvailable || hasCompletedInitialImport
        }
    }

    // MARK: Account

    private func observeAccountChanges() {
        let token = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAccountStatus()
            }
        }
        observerTokens.append(token)
    }

    private func refreshAccountStatus() async {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            Logger.sync.error("Account status check failed: \(String(describing: error), privacy: .public)")
            accountAvailable = nil
            accountIssue = .waitingToRetry("Couldn't reach iCloud to check your account. Sync will retry automatically.")
            recomputeState()
            return
        }

        switch status {
        case .available:
            accountAvailable = true
            accountIssue = nil
            let userRecordName = try? await container.userRecordID().recordName
            detectAccountSwitch(currentUser: userRecordName)
        case .noAccount:
            accountAvailable = false
            accountIssue = .unavailable(reason: "Not signed into iCloud on this device. Your data is saved on this device only.")
            detectAccountSwitch(currentUser: nil)
        case .restricted:
            accountAvailable = false
            accountIssue = .unavailable(reason: "iCloud is restricted on this device (Screen Time or a device management profile). Your data is saved on this device only.")
        case .temporarilyUnavailable:
            // Usually means the Apple ID password needs to be re-entered.
            accountAvailable = false
            accountIssue = .needsAction("Open Settings, tap your name, and confirm your Apple ID password to resume syncing.")
        case .couldNotDetermine:
            accountAvailable = nil
            accountIssue = .waitingToRetry("Couldn't check your iCloud account right now. Sync will retry automatically.")
        @unknown default:
            accountAvailable = nil
            accountIssue = .waitingToRetry("Couldn't check your iCloud account right now. Sync will retry automatically.")
        }
        recomputeState()
    }

    /// Compares the signed-in iCloud user with the one seen last time. On a
    /// change, per-account progress is reset so the app doesn't claim a sync
    /// or a finished download that belonged to a different account.
    private func detectAccountSwitch(currentUser: String?) {
        let previous = defaults.string(forKey: Keys.lastUserRecordName)
        if let previous, previous != currentUser {
            Logger.sync.notice("iCloud account changed or signed out since last run.")
            defaults.removeObject(forKey: Keys.lastSync)
            defaults.removeObject(forKey: Keys.initialImportDone)
            hasCompletedInitialImport = false
            latestByType = [:]
            inProgress = [:]
            failureStreak = [:]
            accountChangedNotice = true
        }
        if let currentUser {
            defaults.set(currentUser, forKey: Keys.lastUserRecordName)
        }
    }

    // MARK: Sync events

    private func observeEvents() {
        let token = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else { return }
            // Delivered on the main queue. Handling it synchronously keeps
            // start and end events in order.
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
        observerTokens.append(token)
    }

    private func handle(_ event: Event) {
        guard event.endDate != nil else {
            inProgress[event.identifier] = event.startDate
            recomputeState()
            return
        }

        inProgress[event.identifier] = nil
        latestByType[event.type] = event

        if event.succeeded {
            failureStreak[event.type] = 0
            if event.type == .import, !hasCompletedInitialImport {
                hasCompletedInitialImport = true
                defaults.set(true, forKey: Keys.initialImportDone)
            }
        } else {
            failureStreak[event.type, default: 0] += 1
            let errorText = event.error.map { String(describing: $0) } ?? "no error"
            Logger.sync.error("CloudKit \(Self.name(of: event.type), privacy: .public) failed: \(errorText, privacy: .public)")
        }
        recomputeState()
    }

    private func recomputeState() {
        guard case .cloudKit = storeMode else { return }

        if let accountIssue {
            state = accountIssue
            return
        }

        // Drop start events that never got an end event (for example, the
        // app was suspended mid-sync) so "Syncing…" can't stick forever.
        let staleCutoff = Date().addingTimeInterval(-5 * 60)
        inProgress = inProgress.filter { $0.value > staleCutoff }
        if !inProgress.isEmpty {
            state = .syncing
            return
        }

        let latest = [EventType.setup, .export, .import].compactMap { latestByType[$0] }

        let worstProblem = latest
            .filter { !$0.succeeded }
            .map { problem(for: $0) }
            .max { $0.severity < $1.severity }
        if let worstProblem, let problemState = worstProblem.state {
            state = problemState
            return
        }

        if let newest = latest.filter(\.succeeded).compactMap(\.endDate).max() {
            defaults.set(newest.timeIntervalSince1970, forKey: Keys.lastSync)
            state = .synced(newest)
            return
        }

        let last = defaults.double(forKey: Keys.lastSync)
        state = last > 0 ? .synced(Date(timeIntervalSince1970: last)) : .unknown
    }

    // MARK: Error classification

    private enum SyncProblem {
        /// Routine and handled internally. Not worth showing.
        case ignorable
        case transient(String)
        case needsAction(String)
        case appDefect(code: String)

        var severity: Int {
            switch self {
            case .ignorable: return 0
            case .transient: return 1
            case .needsAction: return 2
            case .appDefect: return 3
            }
        }

        var state: CloudSyncState? {
            switch self {
            case .ignorable:
                return nil
            case .transient(let message):
                return .waitingToRetry(message)
            case .needsAction(let message):
                return .needsAction(message)
            case .appDefect(let code):
                return .error("Sync hit a problem that won't fix itself. Your data is safe on this device. Update Roadworthy or contact support (code \(code)).")
            }
        }
    }

    /// Core Data error codes treated as routine or temporary. 134419 shows up
    /// when the system defers a sync request; 134400 when the iCloud account
    /// isn't available, which the account check reports separately.
    /// Confirm against your own device logs and adjust as you see others.
    private static let ignorableCoreDataCodes: Set<Int> = [134419]
    private static let transientCoreDataCodes: Set<Int> = [134400]

    private func problem(for event: Event) -> SyncProblem {
        guard let error = event.error else {
            return .transient("Sync didn't finish. It will retry automatically.")
        }

        let ckErrors = Self.rootCKErrors(error)
        if !ckErrors.isEmpty {
            return ckErrors
                .map { Self.classify($0.code) }
                .max { $0.severity < $1.severity } ?? .ignorable
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if Self.ignorableCoreDataCodes.contains(nsError.code) { return .ignorable }
            if Self.transientCoreDataCodes.contains(nsError.code) {
                return .transient("Waiting for your iCloud account. Sync will resume automatically.")
            }
        }

        // Unrecognized: give it a few retries before calling it a defect, so
        // a one-off hiccup doesn't raise an alarm.
        let code = StoreMode.code(for: error)
        if failureStreak[event.type, default: 0] >= 3 {
            return .appDefect(code: code)
        }
        return .transient("Sync paused (\(code)). It will retry automatically.")
    }

    /// Finds the CloudKit errors behind an event error. They're often nested
    /// under a Core Data NSError (NSUnderlyingErrorKey) or bundled inside a
    /// partial failure, where each record can fail for a different reason.
    private static func rootCKErrors(_ error: Error) -> [CKError] {
        if let ckError = error as? CKError {
            if ckError.code == .partialFailure, let itemErrors = ckError.partialErrorsByItemID {
                let nested = itemErrors.values.flatMap { rootCKErrors($0) }
                return nested.isEmpty ? [ckError] : nested
            }
            return [ckError]
        }
        if let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error {
            return rootCKErrors(underlying)
        }
        return []
    }

    private static func classify(_ code: CKError.Code) -> SyncProblem {
        switch code {
        case .operationCancelled, .serverRecordChanged, .changeTokenExpired:
            // Handled internally by Core Data's CloudKit mirroring.
            return .ignorable
        case .networkUnavailable, .networkFailure:
            return .transient("No internet connection. Sync will resume automatically once you're back online.")
        case .serviceUnavailable, .requestRateLimited, .zoneBusy, .serverResponseLost, .limitExceeded, .partialFailure:
            return .transient("iCloud is busy. Sync will retry automatically.")
        case .notAuthenticated:
            return .needsAction("Sign in to iCloud in Settings to resume syncing.")
        case .quotaExceeded:
            return .needsAction("Your iCloud storage is full. New entries are saved on this device only until you free up space in Settings > [your name] > iCloud.")
        case .accountTemporarilyUnavailable:
            return .needsAction("Open Settings, tap your name, and confirm your Apple ID password to resume syncing.")
        case .managedAccountRestricted:
            return .needsAction("This Apple ID is managed by an organization that doesn't allow iCloud sync for this app.")
        case .userDeletedZone:
            return .needsAction("Roadworthy's iCloud data was deleted from iCloud settings. Don't delete the app on this device until your vehicles appear on your other devices again.")
        case .incompatibleVersion:
            return .needsAction("Update Roadworthy to keep syncing.")
        default:
            // serverRejectedRequest, badContainer, missingEntitlement,
            // permissionFailure, invalidArguments, badDatabase, internalError,
            // and anything newer. These won't succeed on retry.
            return .appDefect(code: "CK-\(code.rawValue)")
        }
    }

    private static func name(of type: EventType) -> String {
        switch type {
        case .setup: return "setup"
        case .import: return "import"
        case .export: return "export"
        @unknown default: return "event"
        }
    }
}
