import SwiftUI

/// Single row in the workspace sidebar list.
struct WorkspaceRowView: View {
    let name: String
    let color: WorkspaceColor
    let paneCount: Int
    let isActive: Bool
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.color)
                .frame(width: 4, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)

                Text("\(paneCount) pane\(paneCount == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isActive
                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.1))
                : nil
        )
        .contentShape(Rectangle())
    }
}
