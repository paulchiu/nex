import AppKit
@testable import Nex
import Testing

@MainActor
struct MarkdownReviewPopoverTests {
    @Test func commandReturnSubmitsWithoutForwardingKeyDown() throws {
        let textView = ForwardTrackingKeyHandlingTextView(frame: .zero)
        var didSubmit = false
        textView.onCommandEnter = {
            didSubmit = true
        }

        try textView.keyDown(with: #require(keyEvent(
            modifierFlags: .command,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            keyCode: 36
        )))

        #expect(didSubmit)
        #expect(!textView.didForwardUnhandledKeyDown)
    }

    @Test func escapeDismissesWithoutForwardingKeyDown() throws {
        let textView = ForwardTrackingKeyHandlingTextView(frame: .zero)
        var didEscape = false
        textView.onEscape = {
            didEscape = true
        }

        try textView.keyDown(with: #require(keyEvent(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            keyCode: 53
        )))

        #expect(didEscape)
        #expect(!textView.didForwardUnhandledKeyDown)
    }

    @Test func deleteConfirmationDefaultsToCancelNotDelete() {
        let contract = MarkdownReviewPopoverView.deleteConfirmationKeyboardContract

        #expect(contract.cancelHasDefaultAction)
        #expect(contract.cancelHasCancelAction)
        #expect(!contract.deleteHasDefaultAction)
    }

    private func keyEvent(
        modifierFlags: NSEvent.ModifierFlags = [],
        characters: String,
        charactersIgnoringModifiers: String,
        keyCode: UInt16
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

private final class ForwardTrackingKeyHandlingTextView: KeyHandlingTextView {
    var didForwardUnhandledKeyDown = false

    override func forwardUnhandledKeyDown(with _: NSEvent) {
        didForwardUnhandledKeyDown = true
    }
}
