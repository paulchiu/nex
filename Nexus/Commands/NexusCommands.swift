import ComposableArchitecture
import SwiftUI

/// Menu bar keyboard shortcuts for workspace management.
struct NexusCommands: Commands {
    let store: StoreOf<AppReducer>

    var body: some Commands {
        // Replace the default "New Window" (⌘N) with "New Workspace"
        CommandGroup(replacing: .newItem) {
            Button("New Workspace") {
                store.send(.showNewWorkspaceSheet)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()

            // Switch by number: ⌘1–⌘9
            ForEach(0..<9, id: \.self) { index in
                Button("Switch to Workspace \(index + 1)") {
                    store.send(.switchToWorkspaceByIndex(index))
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
            }

            Divider()

            Button("Next Workspace") {
                store.send(.switchToNextWorkspace)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Previous Workspace") {
                store.send(.switchToPreviousWorkspace)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
        }

        // View
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                store.send(.toggleSidebar)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }
}

/// NSEvent monitor for shortcuts that need focused-pane context.
/// These can't go through SwiftUI Commands because they need to know
/// which pane is focused.
@MainActor
final class PaneShortcutMonitor {
    private var monitor: Any?
    private let store: StoreOf<AppReducer>

    init(store: StoreOf<AppReducer>) {
        self.store = store
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard let activeID = store.activeWorkspaceID else { return false }

        // ⌘D — split right
        if event.keyCode == 2 /* d */ && flags == .command {
            store.send(.workspaces(.element(
                id: activeID,
                action: .splitPane(direction: .horizontal, sourcePaneID: nil)
            )))
            return true
        }

        // ⌘⇧D — split down
        if event.keyCode == 2 /* d */ && flags == [.command, .shift] {
            store.send(.workspaces(.element(
                id: activeID,
                action: .splitPane(direction: .vertical, sourcePaneID: nil)
            )))
            return true
        }

        // ⌘W — close pane
        if event.keyCode == 13 /* w */ && flags == .command {
            if let workspace = store.workspaces[id: activeID],
               let focusedID = workspace.focusedPaneID {
                // Don't close if it's the last pane — close the workspace instead
                if workspace.panes.count <= 1 {
                    return false // Let default handling occur
                }
                store.send(.workspaces(.element(
                    id: activeID,
                    action: .closePane(focusedID)
                )))
                return true
            }
            return false
        }

        // ⌘⌥→ — focus next pane
        if event.keyCode == 124 /* right arrow */ && flags == [.command, .option] {
            store.send(.workspaces(.element(
                id: activeID,
                action: .focusNextPane
            )))
            return true
        }

        // ⌘⌥← — focus previous pane
        if event.keyCode == 123 /* left arrow */ && flags == [.command, .option] {
            store.send(.workspaces(.element(
                id: activeID,
                action: .focusPreviousPane
            )))
            return true
        }

        return false
    }
}
