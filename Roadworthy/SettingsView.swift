import SwiftUI

struct SettingsView: View {
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .miles
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .system
    @State private var showingImport = false

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
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingImport) {
                ImportView()
            }
        }
    }
}

#Preview {
    SettingsView()
}
