import SwiftUI
import SwiftData

@main
struct RoadworthyApp: App {
    // A CloudKit-backed container instead of the plain local one — this is
    // what makes your data sync across your devices via iCloud.
    let modelContainer: ModelContainer = {
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
        // Pointing at the exact container name instead of using `.automatic`,
        // since the container in the Apple Developer portal is named
        // "iCloud.com.Jeremy.Roadworthy" — which doesn't match the standard
        // "iCloud." + bundle identifier pattern `.automatic` expects.
        let configuration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private("iCloud.com.Jeremy.Roadworthy")
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the CloudKit-backed ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}

private struct RootView: View {
    @State private var showingSplash = true
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showingOnboarding = false

    var body: some View {
        ZStack {
            VehicleListView()

            if showingSplash {
                SplashScreenView()
                    .transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.4)) {
                showingSplash = false
            }
            if !hasCompletedOnboarding {
                showingOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingView(isPresented: $showingOnboarding)
                .onDisappear {
                    hasCompletedOnboarding = true
                }
        }
    }
}
