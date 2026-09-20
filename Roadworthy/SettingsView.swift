import SwiftUI

struct SettingsView: View {
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .miles
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    @State private var showingImport = false
    @EnvironmentObject private var syncMonitor: CloudSyncMonitor

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Distance Unit", selection: $distanceUnit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Changes how odometer readings and mileage are shown and entered throughout the app.")
                }

                Section {
                    Picker("Language", selection: $appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } footer: {
                    Text("System Default follows your iPhone's own language setting. Choosing a specific language overrides that just for Roadworthy.")
                }

                Section {
                    Button {
                        showingImport = true
                    } label: {
                        Label("Import Data", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Bring over your maintenance and fuel history from another app.")
                }

                syncStatusSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingImport) {
                ImportView()
            }
        }
    }

    @ViewBuilder
    private var syncStatusSection: some View {
        Section {
            HStack(spacing: 12) {
                syncStatusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(syncStatusTitle)
                    if let subtitle = syncStatusSubtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("iCloud Sync")
        } footer: {
            if case .unavailable = syncMonitor.state {
                Text("Open the Settings app, tap your name at the top, then iCloud, to sign in.")
            } else {
                Text("Your data syncs automatically across your devices via iCloud. This can't be triggered manually — it happens on its own in the background.")
            }
        }
    }

    @ViewBuilder
    private var syncStatusIcon: some View {
        switch syncMonitor.state {
        case .unknown:
            Image(systemName: "icloud")
                .foregroundStyle(.secondary)
        case .unavailable:
            Image(systemName: "icloud.slash")
                .foregroundStyle(.orange)
        case .syncing:
            ProgressView()
        case .synced:
            Image(systemName: "checkmark.icloud.fill")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.icloud.fill")
                .foregroundStyle(.orange)
        }
    }

    private var syncStatusTitle: String {
        switch syncMonitor.state {
        case .unknown: return "Checking Sync Status…"
        case .unavailable: return "iCloud Sync Unavailable"
        case .syncing: return "Syncing…"
        case .synced: return "Synced"
        case .error: return "Sync Issue"
        }
    }

    private var syncStatusSubtitle: String? {
        switch syncMonitor.state {
        case .unknown, .syncing:
            return nil
        case .unavailable(let reason):
            return reason
        case .synced(let date):
            return "Last synced \(date.formatted(.relative(presentation: .named)))"
        case .error(let message):
            return message
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(CloudSyncMonitor())
}
