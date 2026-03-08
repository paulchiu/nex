import ComposableArchitecture
import Foundation

/// Owns all SurfaceView instances across all workspaces.
/// Surfaces persist across workspace switches — they're removed from the
/// view hierarchy but kept alive so PTY processes continue running.
final class SurfaceManager: Sendable {
    private let lock = NSLock()
    // nonisolated(unsafe) because access is protected by lock
    nonisolated(unsafe) private var surfaces: [UUID: SurfaceView] = [:]

    @MainActor
    func createSurface(paneID: UUID, workingDirectory: String) {
        let surface = SurfaceView(paneID: paneID, workingDirectory: workingDirectory)
        lock.withLock {
            surfaces[paneID] = surface
        }
    }

    func surface(for paneID: UUID) -> SurfaceView? {
        lock.withLock {
            surfaces[paneID]
        }
    }

    @MainActor
    func destroySurface(paneID: UUID) {
        let surfaceView = lock.withLock {
            surfaces.removeValue(forKey: paneID)
        }
        surfaceView?.ghosttySurface?.destroy()
        surfaceView?.ghosttySurface = nil  // Prevent double-free in SurfaceView.deinit
    }

    @MainActor
    func destroyAll() {
        let all = lock.withLock {
            let copy = surfaces
            surfaces.removeAll()
            return copy
        }
        for (_, surfaceView) in all {
            surfaceView.ghosttySurface?.destroy()
            surfaceView.ghosttySurface = nil
        }
    }

    var activeSurfaceCount: Int {
        lock.withLock { surfaces.count }
    }
}

// MARK: - TCA Dependency

extension SurfaceManager: DependencyKey {
    static let liveValue = SurfaceManager()
    static let testValue = SurfaceManager()
}

extension DependencyValues {
    var surfaceManager: SurfaceManager {
        get { self[SurfaceManager.self] }
        set { self[SurfaceManager.self] = newValue }
    }
}
