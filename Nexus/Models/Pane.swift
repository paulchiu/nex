import Foundation

struct Pane: Identifiable, Equatable, Sendable {
    let id: UUID
    var label: String?
    var type: PaneType
    var workingDirectory: String
    var createdAt: Date
    var lastActivityAt: Date

    init(
        id: UUID = UUID(),
        label: String? = nil,
        type: PaneType = .shell,
        workingDirectory: String = NSHomeDirectory(),
        createdAt: Date = Date(),
        lastActivityAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.workingDirectory = workingDirectory
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
    }
}
