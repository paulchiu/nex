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
}
