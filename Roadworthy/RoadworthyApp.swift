import SwiftUI
import SwiftData
import OSLog

// TODO: Replace with the real support address before release.
enum SupportConfig {
    static let email = "support@example.com"
}

@main
struct RoadworthyApp: App {
    private let modelContainer: ModelContainer
    private let storeMode: StoreMode

    init() {
        let result = Self.makeContainer()
        modelContainer = result.container
        storeMode = result.mode
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeMode: storeMode)
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Container setup

    /// Opens the CloudKit-backed store. If that fails:
    /// - DEBUG: crash immediately. A failure here almost always means a
    ///   model or entitlement change broke CloudKit's rules, and in a
    ///   release build it would silently turn off sync for every user.
    /// - Release: reopen the same data file without sync, record that it
    ///   happened, and tell the person through `StoreMode.localOnly`.
    /// - If even that fails: an in-memory placeholder plus a recovery screen
    ///   instead of a crash loop. The data file is left untouched so an
    ///   update can recover it.
    ///
    /// Testing the fallback: in DEBUG, add the launch argument
    /// `-ForceLocalOnlyStore` (Edit Scheme > Run > Arguments).
    private static func makeContainer() -> (container: ModelContainer, mode: StoreMode) {
        let schema = Schema([
            Vehicle.self,
            MaintenanceRecord.self,
            FuelLog.self,
            ExpenseRecord.self,
            VehicleDocument.self,
            MaintenanceReminder.self,
            VehicleSpec.self,
            TripLog.self
        ])

        #if DEBUG
        let forceLocalOnly = ProcessInfo.processInfo.arguments.contains("-ForceLocalOnlyStore")
        #else
        let forceLocalOnly = false
        #endif

        var failureCode = "forced"
        if !forceLocalOnly {
            do {
                let cloud = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .private(CloudKitConfig.containerID)
                )
                let container = try ModelContainer(for: schema, configurations: [cloud])
                LocalOnlyRecord.clear()
                return (container, .cloudKit)
            } catch {
                Logger.sync.fault("CloudKit-backed store failed to load: \(String(describing: error), privacy: .public)")
                #if DEBUG
                fatalError("CloudKit store failed to load. In a release build this would silently turn off sync for every user. Check recent model or entitlement changes: \(error)")
                #else
                failureCode = StoreMode.code(for: error)
                #endif
            }
        }

        do {
            // Same default store file, opened without sync, so the person
            // keeps seeing their existing data. See the review notes (item 3)
            // on verifying that entries saved in this mode persist and later
            // upload.
            let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [local])
            return (container, .localOnly(code: failureCode, since: LocalOnlyRecord.markStarted()))
        } catch {
            Logger.sync.fault("Local store also failed to load: \(String(describing: error), privacy: .public)")
            let code = StoreMode.code(for: error)
            do {
                let placeholder = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                return (try ModelContainer(for: schema, configurations: [placeholder]), .failed(code: code))
            } catch {
                // An in-memory store failing means the schema itself can't
                // load, which can only come from a broken build.
                fatalError("Could not create even an in-memory ModelContainer: \(error)")
            }
        }
    }
}

/// Remembers when local-only mode started, so the message can say how long
/// changes have been unsynced. Cleared on the next successful CloudKit launch.
private enum LocalOnlyRecord {
    private static let key = "localOnlyStoreSince"

    static func markStarted() -> Date {
        if let existing = UserDefaults.standard.object(forKey: key) as? Date {
            return existing
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: key)
        return now
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Root view

private struct RootView: View {
    let storeMode: StoreMode

    @StateObject private var syncMonitor: CloudSyncMonitor
    @Query private var allVehicles: [Vehicle]

    @State private var showingSplash = true
    @State private var splashFinished = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false
    @AppStorage("hasSeenImportPrompt") private var hasSeenImportPrompt = false
    @State private var showingImportPrompt = false
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system

    init(storeMode: StoreMode) {
        self.storeMode = storeMode
        _syncMonitor = StateObject(wrappedValue: CloudSyncMonitor(storeMode: storeMode))
    }

    var body: some View {
        if case .failed(let code) = storeMode {
            StoreRecoveryView(code: code)
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        ZStack {
            VehicleListView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    syncBanner
                }

            if showingSplash {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        .environment(\.locale, appLanguage.locale ?? Locale.autoupdatingCurrent)
        .environmentObject(syncMonitor)
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.4)) {
                showingSplash = false
            }
            splashFinished = true
            if !hasCompletedOnboarding {
                showingOnboarding = true
            } else {
                offerImportPromptIfAppropriate()
            }
        }
        // The prompt can be held back while iCloud data downloads. Offer it
        // once that finishes.
        .onChange(of: syncMonitor.canOfferImport) { _, _ in
            offerImportPromptIfAppropriate()
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(isPresented: $showingOnboarding)
                .onDisappear {
                    hasCompletedOnboarding = true
                    offerImportPromptIfAppropriate()
                }
        }
        .sheet(isPresented: $showingImportPrompt) {
            ImportPromptView(isPresented: $showingImportPrompt)
                .onDisappear {
                    hasSeenImportPrompt = true
                }
        }
    }

    /// Only one banner shows at a time, most important first.
    @ViewBuilder
    private var syncBanner: some View {
        if let message = syncMonitor.state.bannerMessage {
            SyncBanner(systemImage: "exclamationmark.icloud.fill", message: message, tint: .orange)
        } else if syncMonitor.isWaitingForInitialImport && allVehicles.isEmpty {
            SyncBanner(
                systemImage: "icloud.and.arrow.down",
                message: "Checking iCloud for your vehicles. On a new device this can take a few minutes.",
                tint: .secondary
            )
        } else if syncMonitor.accountChangedNotice && allVehicles.isEmpty {
            SyncBanner(
                systemImage: "person.crop.circle.badge.exclamationmark",
                message: "Your iCloud account changed. Vehicles saved under a previously signed-in Apple ID will reappear if you sign back into that account.",
                tint: .orange
            )
        }
    }

    /// The first-run import prompt is how a second device ends up with a
    /// full duplicate set: the list is empty because iCloud hasn't finished
    /// downloading yet, so the person imports the same file again. The prompt
    /// waits until the first download finishes, and is skipped entirely if
    /// vehicles already exist.
    private func offerImportPromptIfAppropriate() {
        guard splashFinished, hasCompletedOnboarding, !showingOnboarding,
              !hasSeenImportPrompt, !showingImportPrompt
        else { return }
        guard syncMonitor.canOfferImport else { return }
        guard allVehicles.isEmpty else {
            // Data is already here (likely synced from another device).
            hasSeenImportPrompt = true
            return
        }
        showingImportPrompt = true
    }
}

// MARK: - Banner

private struct SyncBanner: View {
    let systemImage: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Recovery screen

/// Shown instead of the app when no data store could be opened. The goal is
/// to stop the person from deleting the app, since that would erase data
/// that may not have synced.
private struct StoreRecoveryView: View {
    let code: String

    private var supportURL: URL? {
        let subject = "Roadworthy data error \(code)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(SupportConfig.email)?subject=\(subject)")
    }

    var body: some View {
        ContentUnavailableView {
            Label("Roadworthy Can't Open Your Data", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("Your records are still on this device. Please don't delete the app, because that would erase them. Check for an app update, make sure your device has free storage, and restart it. If this keeps happening, contact support with code \(code).")
        } actions: {
            if let supportURL {
                Link("Contact Support", destination: supportURL)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
