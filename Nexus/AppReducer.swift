import ComposableArchitecture
import Foundation

@Reducer
struct AppReducer {
    @ObservableState
    struct State: Equatable {
        var workspaces: IdentifiedArrayOf<WorkspaceFeature.State> = []
        var activeWorkspaceID: UUID?
        var isSidebarVisible: Bool = true
        var isNewWorkspaceSheetPresented: Bool = false

        var activeWorkspace: WorkspaceFeature.State? {
            guard let id = activeWorkspaceID else { return nil }
            return workspaces[id: id]
        }
    }

    enum Action: Equatable, Sendable {
        case appLaunched
        case createWorkspace(name: String, color: WorkspaceColor)
        case deleteWorkspace(UUID)
        case setActiveWorkspace(UUID)
        case switchToWorkspaceByIndex(Int)
        case switchToNextWorkspace
        case switchToPreviousWorkspace
        case toggleSidebar
        case showNewWorkspaceSheet
        case dismissNewWorkspaceSheet
        case persistState
        case stateLoaded(IdentifiedArrayOf<WorkspaceFeature.State>, activeWorkspaceID: UUID?)
        case workspaces(IdentifiedActionOf<WorkspaceFeature>)
    }

    @Dependency(\.surfaceManager) var surfaceManager
    @Dependency(\.persistenceService) var persistenceService
    @Dependency(\.uuid) var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appLaunched:
                return .run { send in
                    let (workspaces, activeID) = await persistenceService.load()
                    await send(.stateLoaded(workspaces, activeWorkspaceID: activeID))
                }

            case .createWorkspace(let name, let color):
                let workspace = WorkspaceFeature.State(
                    id: uuid(),
                    name: name,
                    color: color
                )
                state.workspaces.append(workspace)
                state.activeWorkspaceID = workspace.id
                state.isNewWorkspaceSheetPresented = false

                // Create the initial surface for the default pane
                let paneID = workspace.panes.first!.id
                let cwd = workspace.panes.first!.workingDirectory
                return .merge(
                    .run { _ in
                        await surfaceManager.createSurface(paneID: paneID, workingDirectory: cwd)
                    },
                    .send(.persistState)
                )

            case .deleteWorkspace(let id):
                guard let workspace = state.workspaces[id: id] else { return .none }
                let paneIDs = workspace.layout.allPaneIDs
                state.workspaces.remove(id: id)

                if state.activeWorkspaceID == id {
                    state.activeWorkspaceID = state.workspaces.first?.id
                }

                return .merge(
                    .run { _ in
                        for paneID in paneIDs {
                            await surfaceManager.destroySurface(paneID: paneID)
                        }
                    },
                    .send(.persistState)
                )

            case .setActiveWorkspace(let id):
                state.activeWorkspaceID = id
                state.workspaces[id: id]?.lastAccessedAt = Date()
                return .send(.persistState)

            case .switchToWorkspaceByIndex(let index):
                guard index >= 0, index < state.workspaces.count else { return .none }
                let workspace = state.workspaces[state.workspaces.index(state.workspaces.startIndex, offsetBy: index)]
                return .send(.setActiveWorkspace(workspace.id))

            case .switchToNextWorkspace:
                guard let current = state.activeWorkspaceID,
                      let currentIndex = state.workspaces.index(id: current) else { return .none }
                let nextIndex = (currentIndex + 1) % state.workspaces.count
                let next = state.workspaces[state.workspaces.index(state.workspaces.startIndex, offsetBy: nextIndex)]
                return .send(.setActiveWorkspace(next.id))

            case .switchToPreviousWorkspace:
                guard let current = state.activeWorkspaceID,
                      let currentIndex = state.workspaces.index(id: current) else { return .none }
                let prevIndex = (currentIndex - 1 + state.workspaces.count) % state.workspaces.count
                let prev = state.workspaces[state.workspaces.index(state.workspaces.startIndex, offsetBy: prevIndex)]
                return .send(.setActiveWorkspace(prev.id))

            case .toggleSidebar:
                state.isSidebarVisible.toggle()
                return .none

            case .showNewWorkspaceSheet:
                state.isNewWorkspaceSheetPresented = true
                return .none

            case .dismissNewWorkspaceSheet:
                state.isNewWorkspaceSheetPresented = false
                return .none

            case .persistState:
                let workspaces = state.workspaces
                let activeID = state.activeWorkspaceID
                return .run { _ in
                    await persistenceService.save(workspaces: workspaces, activeWorkspaceID: activeID)
                }

            case .stateLoaded(let workspaces, let activeID):
                if workspaces.isEmpty {
                    // First launch — create a default workspace
                    return .send(.createWorkspace(name: "Default", color: .blue))
                }
                state.workspaces = workspaces
                state.activeWorkspaceID = activeID ?? workspaces.first?.id

                // Create surfaces for all panes in all workspaces
                return .run { _ in
                    for workspace in workspaces {
                        for pane in workspace.panes {
                            await surfaceManager.createSurface(
                                paneID: pane.id,
                                workingDirectory: pane.workingDirectory
                            )
                        }
                    }
                }

            case .workspaces:
                // Child workspace actions — persist after mutations
                return .send(.persistState)
            }
        }
        .forEach(\.workspaces, action: \.workspaces) {
            WorkspaceFeature()
        }
    }
}
