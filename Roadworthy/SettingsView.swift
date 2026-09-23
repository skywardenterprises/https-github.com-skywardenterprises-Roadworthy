import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingKey.distanceUnit) private var distanceUnit: DistanceUnit = .miles
    @AppStorage(SettingKey.appLanguage) private var appLanguage: AppLanguage = .system
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
                    Text("Changes how odometer readings and distances are shown and entered throughout the app. Fuel is still recorded in gallons and fuel economy shown in MPG.")
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
            Text(syncMonitor.state.footer)
        }
    }

    @ViewBuilder
    private var syncStatusIcon: some View {
        if let name = syncMonitor.state.systemImage {
            Image(systemName: name)
                .foregroundStyle(syncStatusTint)
        } else {
            ProgressView()
        }
    }

    /// Kept outside the ViewBuilder so it can use plain `if` and `return`.
    private var syncStatusTint: Color {
        if syncMonitor.state.needsAttention { return .orange }
        if case .synced = syncMonitor.state { return .green }
        return .secondary
    }

    private var syncStatusTitle: String {
        syncMonitor.state.title
    }

    private var syncStatusSubtitle: String? {
        syncMonitor.state.subtitle
    }
}

#Preview {
    SettingsView()
        .environmentObject(CloudSyncMonitor())
}
