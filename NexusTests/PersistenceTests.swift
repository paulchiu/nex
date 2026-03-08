import ComposableArchitecture
import Foundation
import Testing

@testable import Nexus

@Suite("Persistence")
struct PersistenceTests {
    @Test func roundTripSaveAndLoad() async throws {
        let db = try DatabaseService(inMemory: true)
        let persistence = PersistenceService(db: db)

        // Create test state
        let paneID = UUID()
        let pane = Pane(
            id: paneID,
            label: "test",
            type: .shell,
            workingDirectory: "/tmp",
            createdAt: Date(timeIntervalSince1970: 1000),
            lastActivityAt: Date(timeIntervalSince1970: 2000)
        )

        let wsID = UUID()
        let workspace = WorkspaceFeature.State(
            id: wsID,
            name: "Test Workspace",
            color: .green,
            panes: [pane],
            layout: .leaf(paneID),
            focusedPaneID: paneID,
            createdAt: Date(timeIntervalSince1970: 1000),
            lastAccessedAt: Date(timeIntervalSince1970: 2000)
        )

        var workspaces = IdentifiedArrayOf<WorkspaceFeature.State>()
        workspaces.append(workspace)

        // Save (bypass debounce by calling directly)
        await persistence.save(workspaces: workspaces, activeWorkspaceID: wsID)
        // Wait for debounce
        try await Task.sleep(for: .seconds(1))

        // Load
        let (loaded, activeID) = await persistence.load()

        #expect(loaded.count == 1)
        #expect(activeID == wsID)

        let loadedWS = loaded.first!
        #expect(loadedWS.id == wsID)
        #expect(loadedWS.name == "Test Workspace")
        #expect(loadedWS.color == .green)
        #expect(loadedWS.panes.count == 1)
        #expect(loadedWS.panes.first!.workingDirectory == "/tmp")
        #expect(loadedWS.layout == .leaf(paneID))
        #expect(loadedWS.focusedPaneID == paneID)
    }

    @Test func loadEmptyDatabaseReturnsEmpty() async throws {
        let db = try DatabaseService(inMemory: true)
        let persistence = PersistenceService(db: db)

        let (workspaces, activeID) = await persistence.load()
        #expect(workspaces.isEmpty)
        #expect(activeID == nil)
    }

    @Test func multipleWorkspacesPersistOrder() async throws {
        let db = try DatabaseService(inMemory: true)
        let persistence = PersistenceService(db: db)

        let ws1 = WorkspaceFeature.State(name: "First", color: .red)
        let ws2 = WorkspaceFeature.State(name: "Second", color: .blue)
        let ws3 = WorkspaceFeature.State(name: "Third", color: .green)

        var workspaces = IdentifiedArrayOf<WorkspaceFeature.State>()
        workspaces.append(ws1)
        workspaces.append(ws2)
        workspaces.append(ws3)

        await persistence.save(workspaces: workspaces, activeWorkspaceID: ws2.id)
        try await Task.sleep(for: .seconds(1))

        let (loaded, activeID) = await persistence.load()
        #expect(loaded.count == 3)
        #expect(loaded[0].name == "First")
        #expect(loaded[1].name == "Second")
        #expect(loaded[2].name == "Third")
        #expect(activeID == ws2.id)
    }
}
