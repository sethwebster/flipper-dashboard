import SwiftUI

@main
struct FlipperDashboardApp: App {
    @StateObject private var controller = DashboardController()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(controller: controller)
                .onAppear {
                    controller.startLiveUpdates()
                }
                .onDisappear {
                    controller.stopLiveUpdates()
                }
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .accessibilityLabel("Flipper Dashboard")
        }
        .menuBarExtraStyle(.window)
    }
}
