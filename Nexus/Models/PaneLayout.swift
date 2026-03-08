import Foundation

indirect enum PaneLayout: Equatable, Codable, Sendable {
    case leaf(UUID)
    case split(SplitDirection, ratio: Double, first: PaneLayout, second: PaneLayout)
    case empty

    enum SplitDirection: String, Codable, Sendable {
        case horizontal  // side by side (⌘D)
        case vertical    // stacked (⌘⇧D)
    }

    // MARK: - Queries

    var allPaneIDs: [UUID] {
        switch self {
        case .leaf(let id):
            return [id]
        case .split(_, _, let first, let second):
            return first.allPaneIDs + second.allPaneIDs
        case .empty:
            return []
        }
    }

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    func contains(paneID: UUID) -> Bool {
        allPaneIDs.contains(paneID)
    }

    // MARK: - Mutations

    func replacing(paneID: UUID, with replacement: PaneLayout) -> PaneLayout {
        switch self {
        case .leaf(let id):
            return id == paneID ? replacement : self
        case .split(let direction, let ratio, let first, let second):
            return .split(
                direction,
                ratio: ratio,
                first: first.replacing(paneID: paneID, with: replacement),
                second: second.replacing(paneID: paneID, with: replacement)
            )
        case .empty:
            return self
        }
    }

    func removing(paneID: UUID) -> PaneLayout {
        switch self {
        case .leaf(let id):
            return id == paneID ? .empty : self
        case .split(let direction, let ratio, let first, let second):
            let newFirst = first.removing(paneID: paneID)
            let newSecond = second.removing(paneID: paneID)
            if newFirst.isEmpty { return newSecond }
            if newSecond.isEmpty { return newFirst }
            return .split(direction, ratio: ratio, first: newFirst, second: newSecond)
        case .empty:
            return self
        }
    }

    /// Split an existing leaf pane into two panes.
    /// Returns the new layout and the ID of the newly created pane.
    func splitting(
        paneID: UUID,
        direction: SplitDirection,
        newPaneID: UUID = UUID()
    ) -> (layout: PaneLayout, newPaneID: UUID) {
        let splitNode = PaneLayout.split(
            direction,
            ratio: 0.5,
            first: .leaf(paneID),
            second: .leaf(newPaneID)
        )
        return (replacing(paneID: paneID, with: splitNode), newPaneID)
    }

    // MARK: - Focus Navigation

    func nextPaneID(after currentID: UUID) -> UUID? {
        let ids = allPaneIDs
        guard let index = ids.firstIndex(of: currentID), ids.count > 1 else { return nil }
        return ids[(index + 1) % ids.count]
    }

    func previousPaneID(before currentID: UUID) -> UUID? {
        let ids = allPaneIDs
        guard let index = ids.firstIndex(of: currentID), ids.count > 1 else { return nil }
        return ids[(index - 1 + ids.count) % ids.count]
    }

    // MARK: - Split Ratio Updates

    /// Update the ratio of the split node whose first child contains `firstChildPaneID`.
    func updatingSplitRatio(firstChildPaneID: UUID, to newRatio: Double) -> PaneLayout {
        let clamped = min(max(newRatio, 0.1), 0.9)
        switch self {
        case .leaf, .empty:
            return self
        case .split(let direction, let ratio, let first, let second):
            if first.contains(paneID: firstChildPaneID) && !second.contains(paneID: firstChildPaneID) {
                // This split's first child contains the target — update this node's ratio
                // But only if the pane is a direct leaf or we're at the right level
                if case .leaf = first {
                    return .split(direction, ratio: clamped, first: first, second: second)
                }
                // Recurse into the first child
                let updatedFirst = first.updatingSplitRatio(firstChildPaneID: firstChildPaneID, to: newRatio)
                if updatedFirst != first {
                    return .split(direction, ratio: ratio, first: updatedFirst, second: second)
                }
                // The pane wasn't found deeper — this must be the right split
                return .split(direction, ratio: clamped, first: first, second: second)
            }
            // Recurse into second child
            return .split(
                direction,
                ratio: ratio,
                first: first,
                second: second.updatingSplitRatio(firstChildPaneID: firstChildPaneID, to: newRatio)
            )
        }
    }
}
