import Foundation

struct NexTheme: Equatable, Hashable, Identifiable {
    /// Ghostty theme filename (used as the `theme = <id>` config key).
    let id: String
    let displayName: String
}

extension NexTheme {
    static let builtIn: [NexTheme] = [
        NexTheme(id: "Dracula", displayName: "Dracula"),
        NexTheme(id: "Catppuccin Mocha", displayName: "Catppuccin Mocha"),
        NexTheme(id: "Catppuccin Latte", displayName: "Catppuccin Latte"),
        NexTheme(id: "Catppuccin Macchiato", displayName: "Catppuccin Macchiato"),
        NexTheme(id: "Catppuccin Frappe", displayName: "Catppuccin Frappé"),
        NexTheme(id: "Nord", displayName: "Nord"),
        NexTheme(id: "Gruvbox Dark", displayName: "Gruvbox Dark"),
        NexTheme(id: "Gruvbox Light", displayName: "Gruvbox Light"),
        NexTheme(id: "iTerm2 Solarized Dark", displayName: "Solarized Dark"),
        NexTheme(id: "iTerm2 Solarized Light", displayName: "Solarized Light")
    ]

    static func named(_ id: String) -> NexTheme? {
        builtIn.first { $0.id == id }
    }
}
