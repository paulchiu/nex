import AppKit
import Foundation

/// Type-safe wrapper around ghostty_config_t.
final class GhosttyConfig {
    let rawConfig: ghostty_config_t

    init() {
        rawConfig = ghostty_config_new()
        Self.loadNexDefaults(rawConfig)
        ghostty_config_load_default_files(rawConfig)
        ghostty_config_load_recursive_files(rawConfig)
    }

    /// Create a config that loads default + recursive files, then applies
    /// an override file on top. The override file is loaded last so its
    /// values take precedence.
    init(overrideFile path: String) {
        rawConfig = ghostty_config_new()
        Self.loadNexDefaults(rawConfig)
        ghostty_config_load_default_files(rawConfig)
        ghostty_config_load_recursive_files(rawConfig)
        path.withCString { ghostty_config_load_file(rawConfig, $0) }
    }

    /// Apply Nex's opinionated tweaks on top of ghostty's compiled-in
    /// defaults but BEFORE the user's `~/.config/ghostty/config` so any
    /// of these can still be overridden by the user. Order matters:
    /// `loadDefaultFiles` reads the user's XDG / app-support config, so
    /// our defaults must run first to keep user overrides winning.
    private static func loadNexDefaults(_ raw: ghostty_config_t) {
        let path = NSTemporaryDirectory() + "nex-ghostty-defaults"
        try? NexGhosttyDefaults.source.write(
            toFile: path,
            atomically: true,
            encoding: .utf8
        )
        path.withCString { ghostty_config_load_file(raw, $0) }
    }

    func finalize() {
        ghostty_config_finalize(rawConfig)
    }

    // MARK: - Config Getters

    var backgroundOpacity: Double {
        var v = 1.0
        let key = "background-opacity"
        _ = ghostty_config_get(rawConfig, &v, key, UInt(key.count))
        return v
    }

    var backgroundColor: NSColor {
        colorValue(for: "background") ?? .windowBackgroundColor
    }

    var reviewAccentColor: NSColor {
        reviewAccentColor(backgroundColor: backgroundColor)
    }

    func reviewAccentColor(backgroundColor: NSColor) -> NSColor {
        var candidates: [(color: NSColor, bonus: Double)] = []
        if let color = colorValue(for: "cursor-color") {
            candidates.append((color, 0.4))
        }
        candidates += paletteAccentColors().map { ($0, 0.2) }
        if let color = colorValue(for: "selection-background") {
            candidates.append((color, -0.2))
        }

        return Self.bestAccentColor(candidates, background: backgroundColor)
            ?? NSColor.controlAccentColor
    }

    private func colorValue(for key: String) -> NSColor? {
        var color = ghostty_config_color_s(r: 0, g: 0, b: 0)
        if ghostty_config_get(rawConfig, &color, key, UInt(key.count)) {
            return NSColor(
                red: CGFloat(color.r) / 255.0,
                green: CGFloat(color.g) / 255.0,
                blue: CGFloat(color.b) / 255.0,
                alpha: 1.0
            )
        }
        return nil
    }

    private func paletteAccentColors() -> [NSColor] {
        var palette = ghostty_config_palette_s()
        let key = "palette"
        guard ghostty_config_get(rawConfig, &palette, key, UInt(key.count)) else {
            return []
        }

        return withUnsafeBytes(of: &palette) { rawBuffer -> [NSColor] in
            let colors = rawBuffer.bindMemory(to: ghostty_config_color_s.self)
            guard colors.count >= 256 else { return [] }

            let preferredIndexes = [12, 14, 13, 6, 4, 5]
            return preferredIndexes.map { index in
                let color = colors[index]
                return NSColor(
                    red: CGFloat(color.r) / 255.0,
                    green: CGFloat(color.g) / 255.0,
                    blue: CGFloat(color.b) / 255.0,
                    alpha: 1.0
                )
            }
        }
    }

    private static func bestAccentColor(
        _ candidates: [(color: NSColor, bonus: Double)],
        background: NSColor
    ) -> NSColor? {
        let background = background.usingColorSpace(.sRGB) ?? background
        var best: (color: NSColor, score: Double)?

        for candidate in candidates {
            let color = candidate.color.usingColorSpace(.sRGB) ?? candidate.color
            let contrast = contrastRatio(color, background)
            let saturation = saturation(color)
            var score = min(contrast, 4.5) + saturation * 4.0 + candidate.bonus
            if saturation < 0.08 {
                score -= 3.0
            }
            if contrast < 1.4 {
                score -= 2.0
            }
            if best == nil || score > best!.score {
                best = (color, score)
            }
        }

        guard let best, best.score > 1.2 else {
            return nil
        }
        return best.color
    }

    private static func saturation(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let maxComponent = max(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        let minComponent = min(rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        guard maxComponent > 0 else { return 0 }
        return Double((maxComponent - minComponent) / maxComponent)
    }

    private static func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) -> Double {
        let first = relativeLuminance(lhs)
        let second = relativeLuminance(rhs)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ color: NSColor) -> Double {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        func channel(_ value: CGFloat) -> Double {
            let value = Double(value)
            return value <= 0.03928
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent)
            + 0.7152 * channel(rgb.greenComponent)
            + 0.0722 * channel(rgb.blueComponent)
    }

    deinit {
        ghostty_config_free(rawConfig)
    }
}
