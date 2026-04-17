import ComposableArchitecture
import Foundation
@testable import Nex
import Testing

@MainActor
struct WorkspaceGroupRenderTests {
    private static let wsID1 = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private static let wsID2 = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    private static let wsID3 = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    private static let groupID = UUID(uuidString: "30000000-0000-0000-0000-0000000000A1")!

    private static func makeWorkspace(id: UUID, name: String) -> WorkspaceFeature.State {
        let paneID = UUID()
        let pane = Pane(id: paneID)
        return WorkspaceFeature.State(
            id: id,
            name: name,
            slug: name.lowercased(),
            color: .blue,
            panes: [pane],
            layout: .leaf(paneID),
            focusedPaneID: paneID,
            createdAt: Date(timeIntervalSince1970: 1000),
            lastAccessedAt: Date(timeIntervalSince1970: 1000)
        )
    }

    @Test func flatListProducesWorkspaceRowsOnly() {
        let ws1 = Self.makeWorkspace(id: Self.wsID1, name: "A")
        let ws2 = Self.makeWorkspace(id: Self.wsID2, name: "B")
        let state = AppReducer.State(
            workspaces: [ws1, ws2],
            topLevelOrder: [.workspace(Self.wsID1), .workspace(Self.wsID2)]
        )

        let entries = state.renderedEntries
        #expect(entries.count == 2)
        #expect(entries[0] == .workspaceRow(workspaceID: Self.wsID1, depth: 0))
        #expect(entries[1] == .workspaceRow(workspaceID: Self.wsID2, depth: 0))
    }

    @Test func expandedGroupEmitsHeaderThenChildren() {
        let ws1 = Self.makeWorkspace(id: Self.wsID1, name: "A")
        let ws2 = Self.makeWorkspace(id: Self.wsID2, name: "B")
        let group = WorkspaceGroup(
            id: Self.groupID,
            name: "Monitors",
            isCollapsed: false,
            childOrder: [Self.wsID2]
        )
        let state = AppReducer.State(
            workspaces: [ws1, ws2],
            groups: [group],
            topLevelOrder: [.workspace(Self.wsID1), .group(Self.groupID)]
        )

        let entries = state.renderedEntries
        #expect(entries == [
            .workspaceRow(workspaceID: Self.wsID1, depth: 0),
            .groupHeader(groupID: Self.groupID),
            .workspaceRow(workspaceID: Self.wsID2, depth: 1)
        ])
    }

    @Test func collapsedGroupEmitsHeaderOnly() {
        let ws1 = Self.makeWorkspace(id: Self.wsID1, name: "A")
        let ws2 = Self.makeWorkspace(id: Self.wsID2, name: "B")
        let group = WorkspaceGroup(
            id: Self.groupID,
            name: "Monitors",
            isCollapsed: true,
            childOrder: [Self.wsID2]
        )
        let state = AppReducer.State(
            workspaces: [ws1, ws2],
            groups: [group],
            topLevelOrder: [.workspace(Self.wsID1), .group(Self.groupID)]
        )

        let entries = state.renderedEntries
        #expect(entries == [
            .workspaceRow(workspaceID: Self.wsID1, depth: 0),
            .groupHeader(groupID: Self.groupID)
        ])
    }

    @Test func expandedEmptyGroupEmitsPlaceholder() {
        let ws1 = Self.makeWorkspace(id: Self.wsID1, name: "A")
        let group = WorkspaceGroup(
            id: Self.groupID,
            name: "Empty",
            isCollapsed: false,
            childOrder: []
        )
        let state = AppReducer.State(
            workspaces: [ws1],
            groups: [group],
            topLevelOrder: [.workspace(Self.wsID1), .group(Self.groupID)]
        )

        let entries = state.renderedEntries
        #expect(entries == [
            .workspaceRow(workspaceID: Self.wsID1, depth: 0),
            .groupHeader(groupID: Self.groupID),
            .groupEmpty(groupID: Self.groupID)
        ])
    }

    @Test func renderedEntriesSkipsMissingChildren() {
        // childOrder references ws3 but ws3 is not in workspaces; should be filtered.
        let ws1 = Self.makeWorkspace(id: Self.wsID1, name: "A")
        let group = WorkspaceGroup(
            id: Self.groupID,
            name: "Stale",
            isCollapsed: false,
            childOrder: [Self.wsID3]
        )
        let state = AppReducer.State(
            workspaces: [ws1],
            groups: [group],
            topLevelOrder: [.workspace(Self.wsID1), .group(Self.groupID)]
        )

        let entries = state.renderedEntries
        #expect(entries == [
            .workspaceRow(workspaceID: Self.wsID1, depth: 0),
            .groupHeader(groupID: Self.groupID),
            .groupEmpty(groupID: Self.groupID)
        ])
    }

    // MARK: - Reducer tests

    private func makeStore(
        workspaces: IdentifiedArrayOf<WorkspaceFeature.State> = [],
        groups: IdentifiedArrayOf<WorkspaceGroup> = [],
        topLevelOrder: [SidebarID] = [],
        activeWorkspaceID: UUID? = nil
    ) -> TestStoreOf<AppReducer> {
        var appState = AppReducer.State()
        appState.workspaces = workspaces
        appState.groups = groups
        appState.topLevelOrder = topLevelOrder
        appState.activeWorkspaceID = activeWorkspaceID

        let store = TestStore(initialState: appState) {
            AppReducer()
        } withDependencies: {
            $0.surfaceManager = SurfaceManager()
            $0.uuid = .incrementing
            $0.date = .constant(Date(timeIntervalSince1970: 1000))
            $0.gitService.getCurrentBranch = { _ in nil }
            $0.gitService.getStatus = { _ in .clean }
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off(showSkippedAssertions: false)
        return store
    }

    @Test func toggleGroupCollapseFlipsState() async {
        let group = WorkspaceGroup(
            id: Self.groupID,
            name: "Monitors",
            isCollapsed: false,
            childOrder: []
        )
        let store = makeStore(groups: [group], topLevelOrder: [.group(Self.groupID)])

        await store.send(.toggleGroupCollapse(Self.groupID)) { state in
            #expect(state.groups[id: Self.groupID]?.isCollapsed == true)
        }
        await store.send(.toggleGroupCollapse(Self.groupID)) { state in
            #expect(state.groups[id: Self.groupID]?.isCollapsed == false)
        }
    }

    @Test func toggleGroupCollapseIgnoresUnknownGroup() async {
        let store = makeStore()
        let unknownID = UUID(uuidString: "90000000-0000-0000-0000-000000000099")!
        await store.send(.toggleGroupCollapse(unknownID))
    }

    @Test func setActiveWorkspaceAutoExpandsParentGroup() async {
        let ws = Self.makeWorkspace(id: Self.wsID1, name: "Monitor")
        let group = WorkspaceGroup(
            id: Self.groupID,
            name: "Monitors",
            isCollapsed: true,
            childOrder: [Self.wsID1]
        )
        let store = makeStore(
            workspaces: [ws],
            groups: [group],
            topLevelOrder: [.group(Self.groupID)]
        )

        await store.send(.setActiveWorkspace(Self.wsID1)) { state in
            #expect(state.activeWorkspaceID == Self.wsID1)
            #expect(state.groups[id: Self.groupID]?.isCollapsed == false)
        }
    }

    @Test func setActiveWorkspaceLeavesExpandedGroupAlone() async {
        let ws = Self.makeWorkspace(id: Self.wsID1, name: "Monitor")
        let group = WorkspaceGroup(
            id: Self.groupID,
            name: "Monitors",
            isCollapsed: false,
            childOrder: [Self.wsID1]
        )
        let store = makeStore(
            workspaces: [ws],
            groups: [group],
            topLevelOrder: [.group(Self.groupID)]
        )

        await store.send(.setActiveWorkspace(Self.wsID1)) { state in
            #expect(state.activeWorkspaceID == Self.wsID1)
            #expect(state.groups[id: Self.groupID]?.isCollapsed == false)
        }
    }
}
