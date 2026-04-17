import Foundation

enum SidebarID: Hashable, Codable {
    case workspace(UUID)
    case group(UUID)

    var workspaceID: UUID? {
        if case .workspace(let id) = self { return id }
        return nil
    }

    var groupID: UUID? {
        if case .group(let id) = self { return id }
        return nil
    }
}

/// A single entry in the rendered sidebar. The reducer flattens
/// `topLevelOrder` + groups into a `[RenderedEntry]` that the view consumes,
/// honouring per-group collapse state.
enum RenderedEntry: Equatable, Identifiable {
    case workspaceRow(workspaceID: UUID, depth: Int)
    case groupHeader(groupID: UUID)
    case groupEmpty(groupID: UUID)

    var id: String {
        switch self {
        case .workspaceRow(let id, _): "ws:\(id.uuidString)"
        case .groupHeader(let id): "header:\(id.uuidString)"
        case .groupEmpty(let id): "empty:\(id.uuidString)"
        }
    }

    var sidebarID: SidebarID? {
        switch self {
        case .workspaceRow(let id, _): .workspace(id)
        case .groupHeader(let id): .group(id)
        case .groupEmpty: nil
        }
    }
}
