import ComposableArchitecture
import SwiftUI

/// Sidebar list of all workspaces with selection and context menus.
struct WorkspaceListView: View {
    let store: StoreOf<AppReducer>

    var body: some View {
        WithPerceptionTracking {
            List(selection: Binding(
                get: { store.activeWorkspaceID },
                set: { id in
                    if let id { store.send(.setActiveWorkspace(id)) }
                }
            )) {
                ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    WorkspaceRowView(
                        name: workspace.name,
                        color: workspace.color,
                        paneCount: workspace.panes.count,
                        isActive: workspace.id == store.activeWorkspaceID,
                        index: index
                    )
                    .tag(workspace.id)
                    .contextMenu {
                        Button("Rename...") {
                            // TODO: inline rename
                        }
                        Menu("Color") {
                            ForEach(WorkspaceColor.allCases) { color in
                                Button(color.displayName) {
                                    store.send(.workspaces(.element(id: workspace.id, action: .setColor(color))))
                                }
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            store.send(.deleteWorkspace(workspace.id))
                        }
                        .disabled(store.workspaces.count <= 1)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                Button(action: { store.send(.showNewWorkspaceSheet) }) {
                    Label("New Workspace", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(12)
            }
        }
    }
}
