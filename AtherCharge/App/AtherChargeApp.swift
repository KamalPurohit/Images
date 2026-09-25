import SwiftUI
import AppIntents

@main
struct AtherChargeApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.isConfigured {
            DashboardView()
        } else {
            WelcomeView()
        }
    }
}

struct AtherShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetChargeStatusIntent(),
            phrases: [
                "Check my scooter charge in \(.applicationName)",
                "Get \(.applicationName) status",
            ],
            shortTitle: "Charge Status",
            systemImageName: "bolt.fill"
        )
    }
}
