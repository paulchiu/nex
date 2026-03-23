import SwiftUI

/// Editable plain-text view for markdown files, wrapping NSTextView.
struct MarkdownEditorView: NSViewRepresentable {
    let paneID: UUID
    let filePath: String
    let isFocused: Bool
    var backgroundColor: NSColor = .textBackgroundColor
    var backgroundOpacity: Double = 1.0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.usesFindBar = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = backgroundColor.withAlphaComponent(backgroundOpacity)
        textView.insertionPointColor = NSColor.textColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.filePath = filePath
        context.coordinator.loadFile()
        textView.delegate = context.coordinator

        return scrollView
    }

    func updateNSView(_: NSScrollView, context: Context) {
        if context.coordinator.filePath != filePath {
            context.coordinator.filePath = filePath
            context.coordinator.loadFile()
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var filePath: String = ""
        private var saveTask: Task<Void, Never>?

        func loadFile() {
            guard !filePath.isEmpty else { return }
            do {
                let content = try String(contentsOfFile: filePath, encoding: .utf8)
                textView?.string = content
            } catch {
                textView?.string = "// Failed to load: \(error.localizedDescription)"
            }
        }

        @preconcurrency
        func textDidChange(_: Notification) {
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.writeToDisk()
            }
        }

        private func writeToDisk() {
            guard !filePath.isEmpty, let content = textView?.string else { return }
            do {
                try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            } catch {
                print("MarkdownEditorView: save failed — \(error)")
            }
        }
    }
}
