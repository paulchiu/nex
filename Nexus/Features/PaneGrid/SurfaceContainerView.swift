import SwiftUI

/// NSViewRepresentable that bridges SurfaceView (NSView) into SwiftUI.
/// Creates surfaces lazily and retrieves them from SurfaceManager by pane ID.
struct SurfaceContainerView: NSViewRepresentable {
    let paneID: UUID
    let workingDirectory: String
    let isFocused: Bool
    @Environment(\.surfaceManager) private var surfaceManager

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        // Create surface lazily if it doesn't exist yet
        if surfaceManager.surface(for: paneID) == nil {
            surfaceManager.createSurface(paneID: paneID, workingDirectory: workingDirectory)
        }

        if let surface = surfaceManager.surface(for: paneID) {
            surface.frame = container.bounds
            surface.autoresizingMask = [.width, .height]
            container.addSubview(surface)

            if isFocused {
                DispatchQueue.main.async {
                    surface.window?.makeFirstResponder(surface)
                }
            }
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let surface = surfaceManager.surface(for: paneID) else { return }

        // Remove any stale subviews that aren't our target surface
        for subview in container.subviews where subview !== surface {
            subview.removeFromSuperview()
        }

        // Add surface to this container if needed
        if surface.superview !== container {
            surface.removeFromSuperview()
            surface.frame = container.bounds
            surface.autoresizingMask = [.width, .height]
            container.addSubview(surface)
        }

        // Handle focus
        if isFocused {
            DispatchQueue.main.async {
                surface.window?.makeFirstResponder(surface)
            }
        }
    }
}

// MARK: - Environment key for SurfaceManager

private struct SurfaceManagerKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = SurfaceManager()
}

extension EnvironmentValues {
    var surfaceManager: SurfaceManager {
        get { self[SurfaceManagerKey.self] }
        set { self[SurfaceManagerKey.self] = newValue }
    }
}
