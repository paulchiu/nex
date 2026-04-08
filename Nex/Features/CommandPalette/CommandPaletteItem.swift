import Foundation

struct CommandPaletteItem: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let workspaceID: UUID
    let workspaceName: String
    let paneID: UUID?
    let workspaceColor: WorkspaceColor
}
