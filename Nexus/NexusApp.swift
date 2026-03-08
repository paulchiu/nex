import ComposableArchitecture
import SwiftUI

@main
struct NexusApp: App {
    @State private var store = Store(initialState: AppReducer.State()) {
        AppReducer()
    }

    @State private var shortcutMonitor: PaneShortcutMonitor?

    static var isTestMode: Bool {
        ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .environment(\.surfaceManager, SurfaceManager.liveValue)
                .frame(minWidth: 600, minHeight: 400)
                .onAppear {
                    guard !Self.isTestMode else { return }

                    // Disable macOS window tabbing
                    NSWindow.allowsAutomaticWindowTabbing = false
                    if let window = NSApp.windows.first {
                        window.tabbingMode = .disallowed
                    }

                    GhosttyApp.shared.start()
                    store.send(.appLaunched)

                    let monitor = PaneShortcutMonitor(store: store)
                    monitor.start()
                    shortcutMonitor = monitor
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            NexusCommands(store: store)
        }
    }
}
