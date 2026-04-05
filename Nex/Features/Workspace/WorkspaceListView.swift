import ComposableArchitecture
import SwiftUI

/// Sidebar list of all workspaces with selection and context menus.
struct WorkspaceListView: View {
    let store: StoreOf<AppReducer>
    @State private var draggedWorkspaceID: UUID?
    @State private var dragCurrentY: CGFloat = 0
    @State private var dragGrabOffset: CGFloat = 0
    @State private var measuredRowHeight: CGFloat = 0

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.scope(state: \.workspaces, action: \.workspaces)) { workspaceStore in
                        workspaceRow(workspaceStore: workspaceStore)
                    }
                }
                .coordinateSpace(name: "workspaceList")
                .padding(.vertical, 4)
            }
            .onPreferenceChange(RowHeightKey.self) { height in
                if height > 0 { measuredRowHeight = height }
            }
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

    private func workspaceRow(workspaceStore: StoreOf<WorkspaceFeature>) -> some View {
        WithPerceptionTracking {
            let workspaceID = workspaceStore.state.id
            let index = store.workspaces.index(id: workspaceID) ?? 0
            let isDragging = draggedWorkspaceID == workspaceID

            let aggregateStatus = aggregateGitStatus(for: workspaceStore.state)

            WorkspaceRowView(
                name: workspaceStore.name,
                color: workspaceStore.color,
                paneCount: workspaceStore.panes.count,
                repoCount: workspaceStore.repoAssociations.count,
                gitStatus: aggregateStatus,
                isActive: workspaceID == store.activeWorkspaceID,
                index: index,
                waitingPaneCount: workspaceStore.panes.count(where: { $0.status == .waitingForInput }),
                hasRunningPanes: workspaceStore.panes.contains { $0.status == .running }
            )
            .padding(.horizontal, 8)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: RowHeightKey.self, value: geo.size.height)
                }
            )
            .offset(y: isDragging ? dragVisualOffset(for: index) : 0)
            .zIndex(isDragging ? 1 : 0)
            .opacity(isDragging ? 0.8 : 1)
            .scaleEffect(isDragging ? 1.03 : 1.0)
            .shadow(color: isDragging ? .black.opacity(0.3) : .clear, radius: 4, y: 2)
            .animation(isDragging ? .none : .easeInOut(duration: 0.15), value: store.workspaces.ids)
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("workspaceList"))
                    .onChanged { value in
                        if draggedWorkspaceID == nil {
                            draggedWorkspaceID = workspaceID
                            dragGrabOffset = value.startLocation.y - CGFloat(index) * measuredRowHeight
                        }
                        dragCurrentY = value.location.y

                        guard measuredRowHeight > 0 else { return }
                        let currentIdx = store.workspaces.index(id: workspaceID) ?? 0
                        let targetIdx = max(0, min(store.workspaces.count - 1,
                                                   Int(value.location.y / measuredRowHeight)))
                        if targetIdx != currentIdx {
                            store.send(.moveWorkspace(id: workspaceID, toIndex: targetIdx))
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            draggedWorkspaceID = nil
                            dragCurrentY = 0
                            dragGrabOffset = 0
                        }
                    }
            )
            .onTapGesture {
                store.send(.setActiveWorkspace(workspaceID))
            }
            .contextMenu {
                Button("Rename...") {
                    store.send(.setRenamingWorkspaceID(workspaceID))
                }
                Menu("Color") {
                    ForEach(WorkspaceColor.allCases) { color in
                        Button(color.displayName) {
                            workspaceStore.send(.setColor(color))
                        }
                    }
                }
                Divider()
                Button("Delete", role: .destructive) {
                    store.send(.deleteWorkspace(workspaceID))
                }
                .disabled(store.workspaces.count <= 1)
            }
        }
    }

    private func dragVisualOffset(for currentIndex: Int) -> CGFloat {
        guard measuredRowHeight > 0 else { return 0 }
        return dragCurrentY - dragGrabOffset - CGFloat(currentIndex) * measuredRowHeight
    }

    /// Aggregate git status: dirty if any association is dirty, clean if all clean, unknown otherwise.
    private func aggregateGitStatus(for workspace: WorkspaceFeature.State) -> RepoGitStatus {
        let statuses = workspace.repoAssociations.map { assoc in
            store.gitStatuses[assoc.id] ?? .unknown
        }
        if statuses.isEmpty { return .unknown }
        if statuses.contains(where: { if case .dirty = $0 { true } else { false } }) {
            let totalChanged = statuses.reduce(0) { total, status in
                if case .dirty(let count) = status { return total + count }
                return total
            }
            return .dirty(changedFiles: totalChanged)
        }
        if statuses.allSatisfy({ $0 == .clean }) {
            return .clean
        }
        return .unknown
    }
}

private struct RowHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > value { value = next }
    }
}
