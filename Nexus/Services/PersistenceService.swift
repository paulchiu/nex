import ComposableArchitecture
import Foundation
import GRDB

/// Debounced state persistence to SQLite via GRDB.
/// Coalesces rapid state changes into a single write.
actor PersistenceService {
    private let db: DatabaseService
    private var pendingTask: Task<Void, Never>?
    private let debounceInterval: Duration = .milliseconds(500)

    init(db: DatabaseService) {
        self.db = db
    }

    // MARK: - Save (debounced)

    func save(
        workspaces: IdentifiedArrayOf<WorkspaceFeature.State>,
        activeWorkspaceID: UUID?
    ) {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.writeToDatabase(workspaces: workspaces, activeWorkspaceID: activeWorkspaceID)
        }
    }

    private func writeToDatabase(
        workspaces: IdentifiedArrayOf<WorkspaceFeature.State>,
        activeWorkspaceID: UUID?
    ) async {
        do {
            try await db.writer.write { db in
                // Clear and re-insert (fast at Phase 1 scale)
                try WorkspaceRecord.deleteAll(db)
                try PaneRecord.deleteAll(db)

                for (index, workspace) in workspaces.enumerated() {
                    let layoutData = try JSONEncoder().encode(workspace.layout)
                    let layoutJSON = String(data: layoutData, encoding: .utf8) ?? "null"

                    let record = WorkspaceRecord(
                        id: workspace.id.uuidString,
                        name: workspace.name,
                        color: workspace.color.rawValue,
                        layoutJSON: layoutJSON,
                        focusedPaneID: workspace.focusedPaneID?.uuidString,
                        createdAt: workspace.createdAt.timeIntervalSince1970,
                        lastAccessedAt: workspace.lastAccessedAt.timeIntervalSince1970,
                        sortOrder: index
                    )
                    try record.insert(db)

                    for pane in workspace.panes {
                        let paneRecord = PaneRecord(
                            id: pane.id.uuidString,
                            workspaceID: workspace.id.uuidString,
                            label: pane.label,
                            type: pane.type.rawValue,
                            workingDirectory: pane.workingDirectory,
                            createdAt: pane.createdAt.timeIntervalSince1970,
                            lastActivityAt: pane.lastActivityAt.timeIntervalSince1970
                        )
                        try paneRecord.insert(db)
                    }
                }

                // Save active workspace
                let stateRecord = AppStateRecord(
                    key: "activeWorkspaceID",
                    value: activeWorkspaceID?.uuidString
                )
                try stateRecord.save(db)
            }
        } catch {
            print("PersistenceService: write failed — \(error)")
        }
    }

    // MARK: - Load

    func load() -> (IdentifiedArrayOf<WorkspaceFeature.State>, activeWorkspaceID: UUID?) {
        do {
            return try db.writer.read { db in
                let workspaceRecords = try WorkspaceRecord
                    .order(Column("sortOrder"))
                    .fetchAll(db)

                var workspaces = IdentifiedArrayOf<WorkspaceFeature.State>()

                for record in workspaceRecords {
                    guard let wsID = UUID(uuidString: record.id) else { continue }

                    let paneRecords = try PaneRecord
                        .filter(Column("workspaceID") == record.id)
                        .fetchAll(db)

                    var panes = IdentifiedArrayOf<Pane>()
                    for pr in paneRecords {
                        guard let paneID = UUID(uuidString: pr.id) else { continue }
                        let pane = Pane(
                            id: paneID,
                            label: pr.label,
                            type: PaneType(rawValue: pr.type) ?? .shell,
                            workingDirectory: pr.workingDirectory,
                            createdAt: Date(timeIntervalSince1970: pr.createdAt),
                            lastActivityAt: Date(timeIntervalSince1970: pr.lastActivityAt)
                        )
                        panes.append(pane)
                    }

                    let layout: PaneLayout
                    if let data = record.layoutJSON.data(using: .utf8) {
                        layout = (try? JSONDecoder().decode(PaneLayout.self, from: data)) ?? .empty
                    } else {
                        layout = .empty
                    }

                    let color = WorkspaceColor(rawValue: record.color) ?? .blue
                    let focusedID = record.focusedPaneID.flatMap(UUID.init)

                    let workspace = WorkspaceFeature.State(
                        id: wsID,
                        name: record.name,
                        color: color,
                        panes: panes,
                        layout: layout,
                        focusedPaneID: focusedID,
                        createdAt: Date(timeIntervalSince1970: record.createdAt),
                        lastAccessedAt: Date(timeIntervalSince1970: record.lastAccessedAt)
                    )
                    workspaces.append(workspace)
                }

                let activeIDStr = try AppStateRecord
                    .filter(Column("key") == "activeWorkspaceID")
                    .fetchOne(db)?
                    .value
                let activeID = activeIDStr.flatMap(UUID.init)

                return (workspaces, activeID)
            }
        } catch {
            print("PersistenceService: load failed — \(error)")
            return ([], nil)
        }
    }
}

// MARK: - TCA Dependency

extension PersistenceService: DependencyKey {
    static var liveValue: PersistenceService {
        let db = try! DatabaseService()
        return PersistenceService(db: db)
    }

    static var testValue: PersistenceService {
        let db = try! DatabaseService(inMemory: true)
        return PersistenceService(db: db)
    }
}

extension DependencyValues {
    var persistenceService: PersistenceService {
        get { self[PersistenceService.self] }
        set { self[PersistenceService.self] = newValue }
    }
}
