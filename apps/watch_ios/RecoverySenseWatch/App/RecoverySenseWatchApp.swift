import SwiftUI

@main
struct RecoverySenseWatchApp: App {
  @StateObject private var model = RecoverySenseWatchModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      WatchDashboardView()
        .environmentObject(model)
        .onAppear { model.start() }
        .onChange(of: scenePhase) { _, newPhase in
          model.setScreenInteractive(newPhase == .active)
        }
    }
  }
}
