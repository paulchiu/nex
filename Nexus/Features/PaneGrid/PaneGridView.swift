import ComposableArchitecture
import SwiftUI

/// Recursively renders a PaneLayout tree as split views.
/// Leaf nodes become terminal surfaces, split nodes become GeometryReader-based containers.
struct PaneGridView: View {
    let layout: PaneLayout
    let panes: IdentifiedArrayOf<Pane>
    let focusedPaneID: UUID?
    let onCreatePane: () -> Void
    let onClosePane: (UUID) -> Void
    let onFocusPane: (UUID) -> Void
    let onUpdateRatio: (UUID, Double) -> Void

    var body: some View {
        LayoutNodeView(
            layout: layout,
            panes: panes,
            focusedPaneID: focusedPaneID,
            onCreatePane: onCreatePane,
            onClosePane: onClosePane,
            onFocusPane: onFocusPane,
            onUpdateRatio: onUpdateRatio
        )
    }
}

/// Separate struct to allow recursive type usage with AnyView.
private struct LayoutNodeView: View {
    let layout: PaneLayout
    let panes: IdentifiedArrayOf<Pane>
    let focusedPaneID: UUID?
    let onCreatePane: () -> Void
    let onClosePane: (UUID) -> Void
    let onFocusPane: (UUID) -> Void
    let onUpdateRatio: (UUID, Double) -> Void

    var body: some View {
        switch layout {
        case .leaf(let paneID):
            if let pane = panes[id: paneID] {
                VStack(spacing: 0) {
                    PaneHeaderView(
                        pane: pane,
                        isFocused: paneID == focusedPaneID,
                        onClose: { onClosePane(paneID) }
                    )

                    SurfaceContainerView(
                        paneID: paneID,
                        workingDirectory: pane.workingDirectory,
                        isFocused: paneID == focusedPaneID
                    )
                    .id(paneID)
                }
                .border(
                    paneID == focusedPaneID ? Color.accentColor.opacity(0.4) : Color.clear,
                    width: 1
                )
            }

        case .split(let direction, let ratio, let first, let second):
            SplitLayoutView(
                direction: direction,
                ratio: ratio,
                first: first,
                second: second,
                panes: panes,
                focusedPaneID: focusedPaneID,
                onCreatePane: onCreatePane,
                onClosePane: onClosePane,
                onFocusPane: onFocusPane,
                onUpdateRatio: onUpdateRatio
            )

        case .empty:
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "terminal")
                    .font(.system(size: 36))
                    .foregroundStyle(.quaternary)
                Text("No panes")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                Button("New Pane") {
                    onCreatePane()
                }
                .keyboardShortcut(.return, modifiers: [])
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Renders a split node with two children and a divider.
private struct SplitLayoutView: View {
    let direction: PaneLayout.SplitDirection
    let ratio: Double
    let first: PaneLayout
    let second: PaneLayout
    let panes: IdentifiedArrayOf<Pane>
    let focusedPaneID: UUID?
    let onCreatePane: () -> Void
    let onClosePane: (UUID) -> Void
    let onFocusPane: (UUID) -> Void
    let onUpdateRatio: (UUID, Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let totalSize = direction == .horizontal
                ? geometry.size.width
                : geometry.size.height
            let dividerSize: CGFloat = 4
            let available = totalSize - dividerSize
            let firstSize = available * ratio
            let secondSize = available * (1 - ratio)
            let firstPaneID = first.allPaneIDs.first

            let firstChild = LayoutNodeView(
                layout: first, panes: panes, focusedPaneID: focusedPaneID,
                onCreatePane: onCreatePane, onClosePane: onClosePane,
                onFocusPane: onFocusPane, onUpdateRatio: onUpdateRatio
            )
            let secondChild = LayoutNodeView(
                layout: second, panes: panes, focusedPaneID: focusedPaneID,
                onCreatePane: onCreatePane, onClosePane: onClosePane,
                onFocusPane: onFocusPane, onUpdateRatio: onUpdateRatio
            )
            let divider = SplitDividerView(direction: direction) { delta in
                guard let id = firstPaneID else { return }
                let newRatio = (firstSize + delta) / available
                onUpdateRatio(id, newRatio)
            }

            if direction == .horizontal {
                HStack(spacing: 0) {
                    firstChild.frame(width: firstSize)
                    divider
                    secondChild.frame(width: secondSize)
                }
            } else {
                VStack(spacing: 0) {
                    firstChild.frame(height: firstSize)
                    divider
                    secondChild.frame(height: secondSize)
                }
            }
        }
    }
}
