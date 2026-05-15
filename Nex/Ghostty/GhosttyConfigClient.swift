import AppKit
import ComposableArchitecture
import SwiftUI

/// Read-only access to ghostty config values.
/// Use `@Dependency(\.ghosttyConfig)` in reducers or `@Environment(\.ghosttyConfig)` in views.
///
/// Populated once after `GhosttyApp.shared.start()` via `GhosttyConfigClient.load()`.
struct GhosttyConfigClient: @unchecked Sendable {
    var backgroundOpacity: Double = 1.0
    var backgroundColor: NSColor = .windowBackgroundColor
    var reviewAccentColor: NSColor = .controlAccentColor

    /// Build from the live ghostty config. Call on main actor after `GhosttyApp.shared.start()`.
    @MainActor
    static func load() -> GhosttyConfigClient {
        guard let config = GhosttyApp.shared.config else { return GhosttyConfigClient() }
        return GhosttyConfigClient(
            backgroundOpacity: config.backgroundOpacity,
            backgroundColor: config.backgroundColor,
            reviewAccentColor: config.reviewAccentColor
        )
    }

    /// Build from live ghostty config, then mirror the saved Nex appearance
    /// override used for pane backgrounds.
    @MainActor
    static func load(applyingSavedAppearanceFrom defaults: UserDefaults) -> GhosttyConfigClient {
        guard let config = GhosttyApp.shared.config else { return GhosttyConfigClient() }
        var client = load()

        if defaults.object(forKey: SettingsFeature.defaultsKeyOpacity) != nil {
            client.backgroundOpacity = defaults.double(forKey: SettingsFeature.defaultsKeyOpacity)
        }
        if defaults.bool(forKey: SettingsFeature.defaultsKeyHasCustomColor) {
            let r = defaults.double(forKey: SettingsFeature.defaultsKeyColorR)
            let g = defaults.double(forKey: SettingsFeature.defaultsKeyColorG)
            let b = defaults.double(forKey: SettingsFeature.defaultsKeyColorB)
            client.backgroundColor = NSColor(red: r, green: g, blue: b, alpha: 1.0)
            client.reviewAccentColor = config.reviewAccentColor(backgroundColor: client.backgroundColor)
        }

        return client
    }
}

// MARK: - TCA Dependency

extension GhosttyConfigClient: DependencyKey {
    /// Populated by NexApp after ghostty starts. Before that, returns defaults.
    nonisolated(unsafe) static var liveValue = GhosttyConfigClient()
    static let testValue = GhosttyConfigClient()
}

extension DependencyValues {
    var ghosttyConfig: GhosttyConfigClient {
        get { self[GhosttyConfigClient.self] }
        set { self[GhosttyConfigClient.self] = newValue }
    }
}

extension EnvironmentValues {
    @Entry var ghosttyConfig: GhosttyConfigClient = .init()
}
