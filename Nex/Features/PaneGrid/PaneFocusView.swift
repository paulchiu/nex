import AppKit

/// Container NSView that posts `SurfaceView.paneFocusedNotification`
/// when its embedded child is clicked, so any pane content (WKWebView,
/// NSTextView, etc.) triggers the same focus flow as terminal surfaces.
///
/// Usage: call `embed(_:)` with the child view. A click gesture recognizer
/// is attached to the child so focus fires regardless of the child's own
/// event handling.
final class PaneFocusView: NSView {
    let paneID: UUID

    init(paneID: UUID) {
        self.paneID = paneID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Embed a child view with Auto Layout constraints filling the container,
    /// and attach a click gesture recognizer for focus notification.
    func embed(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor),
            child.trailingAnchor.constraint(equalTo: trailingAnchor),
            child.topAnchor.constraint(equalTo: topAnchor),
            child.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let clickRecognizer = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleClick(_:))
        )
        clickRecognizer.delaysPrimaryMouseButtonEvents = false
        child.addGestureRecognizer(clickRecognizer)
    }

    @objc private func handleClick(_: NSClickGestureRecognizer) {
        NotificationCenter.default.post(
            name: SurfaceView.paneFocusedNotification,
            object: nil,
            userInfo: ["paneID": paneID]
        )
    }

    // MARK: - Shared scroll position store

    /// Scroll fraction (0–1) preserved across edit/preview mode toggles.
    private static var scrollFractions: [UUID: CGFloat] = [:]

    static func saveScrollFraction(_ fraction: CGFloat, for paneID: UUID) {
        scrollFractions[paneID] = fraction
    }

    static func scrollFraction(for paneID: UUID) -> CGFloat? {
        scrollFractions[paneID]
    }

    static func clearScrollFraction(for paneID: UUID) {
        scrollFractions.removeValue(forKey: paneID)
    }
}
