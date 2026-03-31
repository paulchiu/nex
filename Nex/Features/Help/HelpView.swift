import SwiftUI

// MARK: - Data

struct ShortcutEntry: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
}

struct ShortcutCategory: Identifiable {
    let id = UUID()
    let name: String
    let shortcuts: [ShortcutEntry]
}

enum HelpData {
    static let githubURL = URL(string: "https://github.com/benfriebe/nex")!

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    static let shortcutCategories: [ShortcutCategory] = [
        ShortcutCategory(name: "Workspaces", shortcuts: [
            ShortcutEntry(keys: "⌘N", description: "New Workspace"),
            ShortcutEntry(keys: "⌘1–⌘9", description: "Switch to Workspace by Number"),
            ShortcutEntry(keys: "⌘⌥↓", description: "Next Workspace"),
            ShortcutEntry(keys: "⌘⌥↑", description: "Previous Workspace")
        ]),
        ShortcutCategory(name: "Panes", shortcuts: [
            ShortcutEntry(keys: "⌘D", description: "Split Right"),
            ShortcutEntry(keys: "⌘⇧D", description: "Split Down"),
            ShortcutEntry(keys: "⌘W", description: "Close Pane"),
            ShortcutEntry(keys: "⌘⌥→ / ⌘]", description: "Focus Next Pane"),
            ShortcutEntry(keys: "⌘⌥← / ⌘[", description: "Focus Previous Pane"),
            ShortcutEntry(keys: "⌘⇧↩", description: "Toggle Zoom Pane"),
            ShortcutEntry(keys: "⌘⇧T", description: "Reopen Closed Pane")
        ]),
        ShortcutCategory(name: "Files & Views", shortcuts: [
            ShortcutEntry(keys: "⌘O", description: "Open File"),
            ShortcutEntry(keys: "⌘E", description: "Toggle Markdown Edit/Preview"),
            ShortcutEntry(keys: "⌘⇧S", description: "Toggle Sidebar"),
            ShortcutEntry(keys: "⌘I", description: "Toggle Inspector"),
            ShortcutEntry(keys: "⌘,", description: "Settings")
        ])
    ]
}

// MARK: - Views

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nex")
                            .font(.title.bold())
                        Text("Version \(HelpData.appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Keyboard shortcuts
                Text("Keyboard Shortcuts")
                    .font(.title2.bold())

                ForEach(HelpData.shortcutCategories) { category in
                    ShortcutCategoryView(category: category)
                }

                Divider()

                // Links
                HStack {
                    Link("GitHub Repository", destination: HelpData.githubURL)
                    Spacer()
                }
            }
            .padding(24)
        }
        .frame(width: 420, height: 500)
    }
}

private struct ShortcutCategoryView: View {
    let category: ShortcutCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.name)
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(category.shortcuts) { shortcut in
                HStack {
                    Text(shortcut.keys)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120, alignment: .leading)
                    Text(shortcut.description)
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }
        }
    }
}
