import ComposableArchitecture
import SwiftUI

/// Sheet for creating a new workspace with name and color selection.
struct NewWorkspaceSheet: View {
    let store: StoreOf<AppReducer>

    @State private var name = ""
    @State private var color: WorkspaceColor = .blue

    var body: some View {
        VStack(spacing: 16) {
            Text("New Workspace")
                .font(.headline)

            TextField("Workspace name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)

            HStack(spacing: 8) {
                ForEach(WorkspaceColor.allCases) { c in
                    Circle()
                        .fill(c.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: c == color ? 2 : 0)
                        )
                        .onTapGesture { color = c }
                }
            }

            HStack {
                Button("Cancel") {
                    store.send(.dismissNewWorkspaceSheet)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.send(.createWorkspace(name: trimmed, color: color))
    }
}
