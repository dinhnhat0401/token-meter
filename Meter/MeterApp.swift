import SwiftUI

@main
struct MeterApp: App {
    @StateObject private var refresher = UsageRefresher()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(refresher: refresher) {
                NSApp.terminate(nil)
            }
            .onAppear { refresher.popoverDidOpen() }
            .onDisappear { refresher.popoverDidClose() }
        } label: {
            MenuBarLabel(state: refresher.state)
        }
        .menuBarExtraStyle(.window)
    }
}
