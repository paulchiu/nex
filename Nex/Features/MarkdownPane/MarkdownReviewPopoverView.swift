import AppKit
import SwiftUI

struct MarkdownReviewPopoverView: View {
    enum Purpose {
        case add
        case edit
        case delete
    }

    let purpose: Purpose
    let initialText: String
    let onSubmit: (String) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var draft: String
    @State private var validationMessage: String?

    struct DeleteConfirmationKeyboardContract: Equatable {
        let cancelHasDefaultAction: Bool
        let cancelHasCancelAction: Bool
        let deleteHasDefaultAction: Bool
    }

    static let deleteConfirmationKeyboardContract = DeleteConfirmationKeyboardContract(
        cancelHasDefaultAction: true,
        cancelHasCancelAction: true,
        deleteHasDefaultAction: false
    )

    init(
        purpose: Purpose,
        initialText: String = "",
        onSubmit: @escaping (String) -> Void = { _ in },
        onDelete: @escaping () -> Void = {},
        onCancel: @escaping () -> Void
    ) {
        self.purpose = purpose
        self.initialText = initialText
        self.onSubmit = onSubmit
        self.onDelete = onDelete
        self.onCancel = onCancel
        _draft = State(initialValue: initialText)
    }

    var body: some View {
        switch purpose {
        case .add:
            editorBody(title: "Add comment", primaryTitle: "Add", selectAllOnAppear: false)
        case .edit:
            editorBody(title: "Edit comment", primaryTitle: "Save", selectAllOnAppear: true)
        case .delete:
            deleteBody
        }
    }

    private func editorBody(
        title: String,
        primaryTitle: String,
        selectAllOnAppear: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            MarkdownCommentTextView(
                text: $draft,
                selectAllOnAppear: selectAllOnAppear,
                onCommandEnter: submit,
                onEscape: onCancel
            )
            .frame(width: 292, height: 96)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: submit)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .frame(width: 312)
    }

    private var deleteBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Delete comment?")
                .font(.headline)
            Text("This removes the comment marker from the markdown file.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            deleteButtonRow
        }
        .padding(12)
        .frame(width: 292)
    }

    private var deleteButtonRow: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.defaultAction)
                .keyboardShortcut(.cancelAction)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func submit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "Comment cannot be blank."
            return
        }
        onSubmit(trimmed)
    }
}

private struct MarkdownCommentTextView: NSViewRepresentable {
    @Binding var text: String
    let selectAllOnAppear: Bool
    let onCommandEnter: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = KeyHandlingTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.minSize = NSSize(width: 0, height: 96)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.onCommandEnter = onCommandEnter
        textView.onEscape = onEscape

        context.coordinator.textView = textView
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        textView.onCommandEnter = onCommandEnter
        textView.onEscape = onEscape
        if textView.string != text {
            textView.string = text
        }

        guard !context.coordinator.didFocus else { return }
        context.coordinator.didFocus = true
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
            if selectAllOnAppear {
                textView.selectAll(nil)
            }
        }

        _ = scrollView
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: KeyHandlingTextView?
        var didFocus = false

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

class KeyHandlingTextView: NSTextView {
    var onCommandEnter: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers

        if flags.contains(.command),
           characters == "\r" || characters == "\n" {
            onCommandEnter?()
            return
        }

        if event.keyCode == 53 {
            onEscape?()
            return
        }

        forwardUnhandledKeyDown(with: event)
    }

    func forwardUnhandledKeyDown(with event: NSEvent) {
        super.keyDown(with: event)
    }
}
