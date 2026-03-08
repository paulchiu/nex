import ComposableArchitecture
import SwiftUI

/// Root view: HStack with workspace sidebar + pane grid detail.
struct ContentView: View {
    let store: StoreOf<AppReducer>

    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 0) {
                if store.isSidebarVisible {
                    WorkspaceListView(store: store)
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 300)

                    Divider()
                }

                if let activeID = store.activeWorkspaceID,
                   let workspace = store.workspaces[id: activeID] {
                    PaneGridView(
                        layout: workspace.layout,
                        panes: workspace.panes,
                        focusedPaneID: workspace.focusedPaneID,
                        onCreatePane: {
                            store.send(.workspaces(.element(id: activeID, action: .createPane)))
                        },
                        onClosePane: { paneID in
                            store.send(.workspaces(.element(id: activeID, action: .closePane(paneID))))
                        },
                        onFocusPane: { paneID in
                            store.send(.workspaces(.element(id: activeID, action: .focusPane(paneID))))
                        },
                        onUpdateRatio: { firstChildPaneID, ratio in
                            store.send(.workspaces(.element(
                                id: activeID,
                                action: .updateSplitRatio(firstChildPaneID: firstChildPaneID, ratio: ratio)
                            )))
                        }
                    )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 48))
                            .foregroundStyle(.quaternary)
                        Text("No workspace selected")
                            .foregroundStyle(.secondary)
                        Button("Create Workspace") {
                            store.send(.showNewWorkspaceSheet)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(.default, value: store.isSidebarVisible)
            .sheet(isPresented: Binding(
                get: { store.isNewWorkspaceSheetPresented },
                set: { if !$0 { store.send(.dismissNewWorkspaceSheet) } }
            )) {
                NewWorkspaceSheet(store: store)
            }
            .onReceive(NotificationCenter.default.publisher(for: SurfaceView.paneFocusedNotification)) { notification in
                guard let paneID = notification.userInfo?["paneID"] as? UUID,
                      let activeID = store.activeWorkspaceID,
                      let workspace = store.workspaces[id: activeID],
                      workspace.focusedPaneID != paneID,
                      workspace.panes[id: paneID] != nil else { return }
                store.send(.workspaces(.element(id: activeID, action: .focusPane(paneID))))
            }
        }
    }
}
