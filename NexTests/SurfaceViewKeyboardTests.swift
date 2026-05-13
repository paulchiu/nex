import AppKit
@testable import Nex
import Testing

@MainActor
struct SurfaceViewKeyboardTests {
    private func keyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags = [],
        characters: String = "",
        charactersIgnoringModifiers: String = ""
    ) -> NSEvent {
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
        )!
    }

    @Test func optionIsNotConsumedWhenTranslationDropsOption() {
        let event = keyEvent(
            keyCode: 3,
            modifierFlags: .option,
            characters: "ƒ",
            charactersIgnoringModifiers: "f"
        )

        let key = SurfaceView.keyEvent(
            from: event,
            action: GHOSTTY_ACTION_PRESS,
            translationFlags: []
        )

        #expect(key.mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0)
        #expect(key.consumed_mods.rawValue & GHOSTTY_MODS_ALT.rawValue == 0)
    }

    @Test func optionIsConsumedWhenTranslationKeepsOption() {
        let event = keyEvent(
            keyCode: 3,
            modifierFlags: .option,
            characters: "ƒ",
            charactersIgnoringModifiers: "f"
        )

        let key = SurfaceView.keyEvent(from: event, action: GHOSTTY_ACTION_PRESS)

        #expect(key.mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0)
        #expect(key.consumed_mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0)
    }

    @Test func rightOptionSetsAltSideBit() {
        let rightOption = NSEvent.ModifierFlags(
            rawValue: NSEvent.ModifierFlags.option.rawValue | UInt(NX_DEVICERALTKEYMASK)
        )

        let mods = SurfaceView.mods(fromFlags: rightOption)

        #expect(mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0)
        #expect(mods.rawValue & GHOSTTY_MODS_ALT_RIGHT.rawValue != 0)
    }

    @Test func eventModifierFlagsConvertsVisibleGhosttyMods() {
        let mods = ghostty_input_mods_e(
            rawValue: GHOSTTY_MODS_SHIFT.rawValue
                | GHOSTTY_MODS_CTRL.rawValue
                | GHOSTTY_MODS_ALT.rawValue
                | GHOSTTY_MODS_SUPER.rawValue
                | GHOSTTY_MODS_CAPS.rawValue
        )

        let flags = SurfaceView.eventModifierFlags(fromMods: mods)

        #expect(flags.contains(.shift))
        #expect(flags.contains(.control))
        #expect(flags.contains(.option))
        #expect(flags.contains(.command))
        #expect(flags.contains(.capsLock))
    }

    @Test func ghosttyCharactersPassesThroughPrintableText() {
        let event = keyEvent(
            keyCode: 3,
            characters: "f",
            charactersIgnoringModifiers: "f"
        )

        #expect(SurfaceView.ghosttyCharacters(from: event) == "f")
    }

    @Test func ghosttyCharactersStripsControlForCtrlJ() {
        // Ctrl+J produces U+000A (newline). ghostty handles control-character
        // encoding internally, so we return the un-controlled character ("j")
        // and let ghostty re-encode it based on terminal mode.
        let event = keyEvent(
            keyCode: 0x26,
            modifierFlags: .control,
            characters: "\n",
            charactersIgnoringModifiers: "j"
        )

        #expect(SurfaceView.ghosttyCharacters(from: event) == "j")
    }

    @Test func ghosttyCharactersReturnsNilForPUAFunctionKey() {
        // F1 lives in NSEvent's PUA range (U+F704). Returning it as text would
        // poison ghostty's input; we expect nil so the keycode path handles it.
        let event = keyEvent(
            keyCode: 0x7A,
            characters: "\u{F704}",
            charactersIgnoringModifiers: "\u{F704}"
        )

        #expect(SurfaceView.ghosttyCharacters(from: event) == nil)
    }

    @Test func ghosttyCharactersPassesThroughMultiCharacterStrings() {
        // Multi-scalar strings (dead-key composition, surrogate pairs, etc.)
        // skip the single-character special cases and pass through verbatim.
        let event = keyEvent(
            keyCode: 0,
            characters: "é",
            charactersIgnoringModifiers: "e"
        )

        #expect(SurfaceView.ghosttyCharacters(from: event) == "é")
    }
}
