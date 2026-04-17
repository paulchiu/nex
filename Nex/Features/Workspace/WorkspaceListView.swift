import ComposableArchitecture
import SwiftUI

/// Sidebar list of all workspaces with selection and context menus.
struct WorkspaceListView: View {
    let store: StoreOf<AppReducer>
    @State private var draggedWorkspaceID: UUID?
    @State private var dragCurrentY: CGFloat = 0
    @State private var dragGrabOffset: CGFloat = 0
    @State private var rowHeights: [SidebarID: CGFloat] = [:]

    var body: some View {
        WithPerceptionTracking {
            GeometryReader { outer in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.state.renderedEntries) { entry in
                            entryView(for: entry)
                        }
                        // Trailing flexible spacer that fills remaining
                        // viewport height. Absorbs right-clicks ("New Group"
                        // context menu) below the last row and left-clicks
                        // that should exit an active group rename via the
                        // focus-loss commit path.
                        Color.clear
                            .frame(minHeight: 40, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if store.renamingGroupID != nil {
                                    NSApp.keyWindow?.makeFirstResponder(nil)
                                }
                            }
                            .contextMenu {
                                Button("New Group") {
                                    let placeholder = defaultGroupName(existing: store.groups)
                                    store.send(.createGroup(name: placeholder, autoRename: true))
                                }
                            }
                    }
                    .coordinateSpace(name: "workspaceList")
                    .padding(.vertical, 4)
                    .frame(minHeight: outer.size.height, alignment: .top)
                    .animation(.easeInOut(duration: 0.1), value: store.state.renderedEntries)
                }
                .onPreferenceChange(RowHeightsKey.self) { heights in
                    let validIDs = validSidebarIDs
                    var merged = rowHeights.filter { validIDs.contains($0.key) }
                    for (id, h) in heights where validIDs.contains(id) {
                        merged[id] = h
                    }
                    rowHeights = merged
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                selectionHeader
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: { store.send(.showNewWorkspaceSheet) }) {
                    Label("New Workspace", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(12)
            }
            .confirmationDialog(
                bulkDeleteTitle,
                isPresented: Binding(
                    get: { store.bulkDeleteConfirmationIDs != nil },
                    set: { if !$0 { store.send(.cancelBulkDelete) } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { store.send(.confirmBulkDelete) }
                Button("Cancel", role: .cancel) { store.send(.cancelBulkDelete) }
            } message: {
                Text("This cannot be undone. Panes and surfaces in these workspaces will be closed.")
            }
            .confirmationDialog(
                groupDeleteTitle,
                isPresented: Binding(
                    get: { store.groupDeleteConfirmation != nil },
                    set: { if !$0 { store.send(.cancelGroupDelete) } }
                ),
                titleVisibility: .visible
            ) {
                if let confirmation = store.groupDeleteConfirmation {
                    Button("Move Workspaces to Top Level", role: .destructive) {
                        store.send(.deleteGroup(id: confirmation.groupID, cascade: false))
                    }
                    Button(
                        "Delete Group and \(confirmation.workspaceCount) Workspace\(confirmation.workspaceCount == 1 ? "" : "s")",
                        role: .destructive
                    ) {
                        store.send(.deleteGroup(id: confirmation.groupID, cascade: true))
                    }
                    .disabled(confirmation.workspaceCount == 0)
                    Button("Cancel", role: .cancel) { store.send(.cancelGroupDelete) }
                }
            } message: {
                if let confirmation = store.groupDeleteConfirmation, confirmation.workspaceCount > 0 {
                    Text("Choose whether to also delete the \(confirmation.workspaceCount) workspace\(confirmation.workspaceCount == 1 ? "" : "s") inside this group. Moving them to the top level is the safer option.")
                } else {
                    Text("This group is empty and will be removed.")
                }
            }
            .sheet(isPresented: Binding(
                get: { store.groupBulkCreatePrompt != nil },
                set: { if !$0 { store.send(.cancelBulkCreateGroup) } }
            )) {
                if let prompt = store.groupBulkCreatePrompt {
                    NewGroupSheet(
                        workspaceCount: prompt.workspaceIDs.count,
                        defaultName: defaultGroupName(existing: store.groups),
                        onCreate: { name, color in
                            store.send(.confirmBulkCreateGroup(name: name, color: color))
                        },
                        onCancel: { store.send(.cancelBulkCreateGroup) }
                    )
                }
            }
        }
    }

    // MARK: - Entry rendering

    @ViewBuilder
    private func entryView(for entry: RenderedEntry) -> some View {
        switch entry {
        case .workspaceRow(let workspaceID, let depth):
            if let workspaceStore = store.scope(
                state: \.workspaces[id: workspaceID],
                action: \.workspaces[id: workspaceID]
            ) {
                workspaceRow(workspaceStore: workspaceStore, depth: depth)
            }
        case .groupHeader(let groupID):
            if let group = store.groups[id: groupID] {
                let count = group.childOrder.compactMap { store.workspaces[id: $0] }.count
                GroupHeaderRow(
                    name: group.name,
                    color: group.color,
                    isCollapsed: group.isCollapsed,
                    workspaceCount: count,
                    isRenaming: store.renamingGroupID == groupID,
                    onToggleCollapse: {
                        // If a different group is being renamed, clicking any
                        // row should commit its name via focus loss.
                        if let rid = store.renamingGroupID, rid != groupID {
                            NSApp.keyWindow?.makeFirstResponder(nil)
                        }
                        store.send(.toggleGroupCollapse(groupID))
                    },
                    onCommitRename: { newName in
                        store.send(.renameGroup(id: groupID, name: newName))
                    },
                    onCancelRename: { store.send(.setRenamingGroupID(nil)) }
                )
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: RowHeightsKey.self,
                            value: [.group(groupID): geo.size.height]
                        )
                    }
                )
                .contextMenu {
                    groupContextMenu(groupID: groupID, group: group)
                }
            }
        case .groupEmpty(let groupID):
            GroupEmptyRow()
                .background(
                    GeometryReader { _ in
                        // Empty rows don't participate in drag; no preference needed
                        Color.clear
                    }
                )
                .id("empty-\(groupID.uuidString)")
        }
    }

    private var validSidebarIDs: Set<SidebarID> {
        var ids = Set<SidebarID>()
        for ws in store.workspaces {
            ids.insert(.workspace(ws.id))
        }
        for grp in store.groups {
            ids.insert(.group(grp.id))
        }
        return ids
    }

    @ViewBuilder
    private var selectionHeader: some View {
        let count = store.selectedWorkspaceIDs.count
        if count > 0 {
            HStack(spacing: 8) {
                Text("\(count) selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if count < store.workspaces.count {
                    Button("Select All") { store.send(.selectAllWorkspaces) }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                }
                Button("Clear") { store.send(.clearWorkspaceSelection) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12))
        }
    }

    private var bulkDeleteTitle: String {
        let count = store.bulkDeleteConfirmationIDs?.count ?? 0
        return "Delete \(count) workspace\(count == 1 ? "" : "s")?"
    }

    private var groupDeleteTitle: String {
        if let name = store.groupDeleteConfirmation?.groupName {
            return "Delete \"\(name)\"?"
        }
        return "Delete group?"
    }

    @ViewBuilder
    private func contextMenuContents(
        workspaceID: UUID,
        workspaceStore: StoreOf<WorkspaceFeature>
    ) -> some View {
        let selection = store.selectedWorkspaceIDs
        let isBulkTarget = selection.contains(workspaceID) && selection.count > 1
        if isBulkTarget {
            Text("\(selection.count) workspaces selected")
            Menu("Color All Selected") {
                ForEach(WorkspaceColor.allCases) { color in
                    Button(color.displayName) {
                        store.send(.setBulkColor(color))
                    }
                }
            }
            Button("Group Selected Workspaces...") {
                store.send(.requestBulkCreateGroup)
            }
            Button("Delete \(selection.count) Workspaces...", role: .destructive) {
                store.send(.requestBulkDelete)
            }
            .disabled(selection.count >= store.workspaces.count)
            Divider()
        }
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
        moveToGroupMenu(workspaceID: workspaceID)
        Divider()
        Button("Select All Workspaces") { store.send(.selectAllWorkspaces) }
            .disabled(store.selectedWorkspaceIDs.count >= store.workspaces.count)
        if !store.selectedWorkspaceIDs.isEmpty {
            Button("Deselect All") { store.send(.clearWorkspaceSelection) }
        }
        Divider()
        Button("Delete", role: .destructive) {
            store.send(.deleteWorkspace(workspaceID))
        }
        .disabled(store.workspaces.count <= 1)
    }

    /// "Move to Group ▸" submenu attached to a workspace row's context menu.
    @ViewBuilder
    private func moveToGroupMenu(workspaceID: UUID) -> some View {
        let currentGroupID = store.state.groupID(forWorkspace: workspaceID)
        Menu("Move to Group") {
            if currentGroupID != nil {
                Button("Remove from Group") {
                    store.send(.moveWorkspaceToGroup(
                        workspaceID: workspaceID, groupID: nil, index: nil
                    ))
                }
                Divider()
            }
            if !store.groups.isEmpty {
                ForEach(store.groups) { group in
                    Button(group.name) {
                        store.send(.moveWorkspaceToGroup(
                            workspaceID: workspaceID,
                            groupID: group.id,
                            index: nil
                        ))
                    }
                    .disabled(group.id == currentGroupID)
                }
                Divider()
            }
            Button("New Group...") {
                let placeholder = defaultGroupName(existing: store.groups)
                store.send(.createGroup(
                    name: placeholder,
                    color: nil,
                    insertAfter: nil,
                    initialWorkspaceIDs: [workspaceID],
                    autoRename: true
                ))
            }
        }
    }

    /// Context menu shown on a group header. Handles rename, color, collapse,
    /// and delete (which routes through the confirmation alert).
    @ViewBuilder
    private func groupContextMenu(groupID: UUID, group: WorkspaceGroup) -> some View {
        Button("Rename...") {
            store.send(.beginRenameGroup(groupID))
        }
        Menu("Color") {
            Button("None") {
                store.send(.setGroupColor(id: groupID, color: nil))
            }
            Divider()
            ForEach(WorkspaceColor.allCases) { color in
                Button(color.displayName) {
                    store.send(.setGroupColor(id: groupID, color: color))
                }
            }
        }
        Button(group.isCollapsed ? "Expand" : "Collapse") {
            store.send(.toggleGroupCollapse(groupID))
        }
        Divider()
        Button("Delete Group...", role: .destructive) {
            store.send(.requestGroupDelete(groupID))
        }
    }

    private func workspaceRow(
        workspaceStore: StoreOf<WorkspaceFeature>,
        depth: Int
    ) -> some View {
        WithPerceptionTracking {
            let workspaceID = workspaceStore.state.id
            let flatIndex = store.workspaces.index(id: workspaceID) ?? 0
            let isDragging = draggedWorkspaceID == workspaceID
            // Drag is restricted to top-level workspaces in Phase 2. Grouped
            // workspaces become draggable in Phase 4 with proper drop-target
            // resolution. The gate lives inside `.onChanged` so the gesture is
            // always attached (conditional `.gesture` caused every row's drag
            // to fail — likely due to the optional-Gesture overload).
            let dragEnabled = depth == 0
            let topLevelIndex = store.topLevelOrder.firstIndex(of: .workspace(workspaceID)) ?? 0

            let aggregateStatus = aggregateGitStatus(for: workspaceStore.state)

            WorkspaceRowView(
                name: workspaceStore.name,
                color: workspaceStore.color,
                paneCount: workspaceStore.panes.count,
                repoCount: workspaceStore.repoAssociations.count,
                gitStatus: aggregateStatus,
                isActive: workspaceID == store.activeWorkspaceID,
                index: flatIndex,
                waitingPaneCount: workspaceStore.panes.count(where: { $0.status == .waitingForInput }),
                hasRunningPanes: workspaceStore.panes.contains { $0.status == .running },
                isSelected: store.selectedWorkspaceIDs.contains(workspaceID),
                leadingInset: depth > 0 ? 16 : 0
            )
            .padding(.horizontal, 8)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: RowHeightsKey.self,
                        value: [.workspace(workspaceID): geo.size.height]
                    )
                }
            )
            .offset(y: isDragging ? dragVisualOffset(atTopLevelIndex: topLevelIndex) : 0)
            .zIndex(isDragging ? 1 : 0)
            .opacity(isDragging ? 0.8 : 1)
            .scaleEffect(isDragging ? 1.03 : 1.0)
            .shadow(color: isDragging ? .black.opacity(0.3) : .clear, radius: 4, y: 2)
            .animation(isDragging ? .none : .easeInOut(duration: 0.15), value: store.topLevelOrder)
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("workspaceList"))
                    .onChanged { value in
                        guard dragEnabled, allHeightsMeasured else { return }
                        let currentTopIdx = store.topLevelOrder
                            .firstIndex(of: .workspace(workspaceID)) ?? 0
                        if draggedWorkspaceID == nil {
                            draggedWorkspaceID = workspaceID
                            dragGrabOffset = value.startLocation.y - restMinY(atTopLevelIndex: currentTopIdx)
                        }
                        dragCurrentY = value.location.y

                        if let targetIdx = targetTopLevelIndex(forCursorY: value.location.y),
                           targetIdx != currentTopIdx {
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
                // Clicking any row while a group rename is in progress should
                // commit the rename via focus loss.
                if store.renamingGroupID != nil {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
                let flags = NSEvent.modifierFlags
                if flags.contains(.command) {
                    store.send(.toggleWorkspaceSelection(workspaceID))
                } else if flags.contains(.shift) {
                    store.send(.rangeSelectWorkspace(workspaceID))
                } else {
                    store.send(.clearWorkspaceSelection)
                    store.send(.setActiveWorkspace(workspaceID))
                }
            }
            .contextMenu {
                contextMenuContents(workspaceID: workspaceID, workspaceStore: workspaceStore)
            }
        }
    }

    private var allHeightsMeasured: Bool {
        // Every top-level workspace must be measured, plus every group header.
        // Child workspaces inside expanded groups also need measurement so
        // group-block heights are accurate.
        for item in store.topLevelOrder {
            switch item {
            case .workspace(let id):
                if rowHeights[.workspace(id)] == nil { return false }
            case .group(let gid):
                if rowHeights[.group(gid)] == nil { return false }
                if let group = store.groups[id: gid], !group.isCollapsed {
                    for childID in group.childOrder where store.workspaces[id: childID] != nil {
                        if rowHeights[.workspace(childID)] == nil { return false }
                    }
                }
            }
        }
        return true
    }

    /// Total vertical space consumed by one top-level entry, including any
    /// expanded child workspaces or the empty-group placeholder.
    private func topLevelItemHeight(_ item: SidebarID) -> CGFloat {
        switch item {
        case .workspace(let id):
            return rowHeights[.workspace(id)] ?? 0
        case .group(let gid):
            var h = rowHeights[.group(gid)] ?? 0
            guard let group = store.groups[id: gid], !group.isCollapsed else { return h }
            let children = group.childOrder.filter { store.workspaces[id: $0] != nil }
            if children.isEmpty {
                // GroupEmptyRow is not measured; its approximate laid-out height.
                h += 28
            } else {
                for childID in children {
                    h += rowHeights[.workspace(childID)] ?? 0
                }
            }
            return h
        }
    }

    private func dragVisualOffset(atTopLevelIndex currentIndex: Int) -> CGFloat {
        guard allHeightsMeasured else { return 0 }
        return dragCurrentY - dragGrabOffset - restMinY(atTopLevelIndex: currentIndex)
    }

    /// Cumulative top edge for the top-level entry at `index`.
    private func restMinY(atTopLevelIndex index: Int) -> CGFloat {
        let items = store.topLevelOrder
        var y: CGFloat = 0
        for i in 0 ..< min(index, items.count) {
            y += topLevelItemHeight(items[i])
        }
        return y
    }

    /// Find the top-level slot whose vertical midpoint the cursor has crossed.
    /// Returns nil while any required row height is still unmeasured.
    private func targetTopLevelIndex(forCursorY cursorY: CGFloat) -> Int? {
        let items = store.topLevelOrder
        guard !items.isEmpty, allHeightsMeasured else { return nil }
        var y: CGFloat = 0
        for (i, item) in items.enumerated() {
            let h = topLevelItemHeight(item)
            if cursorY < y + h / 2 {
                return i
            }
            y += h
        }
        return items.count - 1
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

private struct RowHeightsKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [SidebarID: CGFloat] = [:]
    static func reduce(value: inout [SidebarID: CGFloat], nextValue: () -> [SidebarID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
