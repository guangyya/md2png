import AppKit
import Carbon

enum GlobalShortcutCaptureError: Error, Equatable {
    case missingPrimaryModifier
    case unsupportedKey
}

enum GlobalShortcutCapture {
    static func shortcut(
        from event: NSEvent
    ) -> Result<GlobalShortcut, GlobalShortcutCaptureError> {
        guard let key = key(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        ) else {
            return .failure(.unsupportedKey)
        }

        let modifiers = modifiers(from: event.modifierFlags)
        guard let shortcut = GlobalShortcut(key: key, modifiers: modifiers) else {
            return .failure(.missingPrimaryModifier)
        }
        return .success(shortcut)
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> GlobalShortcut.Modifiers {
        var modifiers: GlobalShortcut.Modifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    static func key(
        keyCode: UInt16,
        charactersIgnoringModifiers: String?
    ) -> GlobalShortcutKey? {
        if let special = specialKey(for: keyCode) {
            return GlobalShortcutKey(
                keyCode: UInt32(keyCode),
                keyEquivalent: special.keyEquivalent,
                displayName: special.displayName,
                accessibilityName: special.accessibilityName
            )
        }

        guard let charactersIgnoringModifiers,
              charactersIgnoringModifiers.count == 1,
              let scalar = charactersIgnoringModifiers.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar) else {
            return nil
        }
        let keyEquivalent = charactersIgnoringModifiers.lowercased()
        guard keyEquivalent.count == 1 else { return nil }
        let displayName = charactersIgnoringModifiers.uppercased()
        guard !displayName.isEmpty else { return nil }
        return GlobalShortcutKey(
            keyCode: UInt32(keyCode),
            keyEquivalent: keyEquivalent,
            displayName: displayName,
            accessibilityName: displayName
        )
    }

    private struct SpecialKey {
        let keyEquivalent: String
        let displayName: String
        let accessibilityName: String
    }

    private static func specialKey(for keyCode: UInt16) -> SpecialKey? {
        switch Int(keyCode) {
        case kVK_Return:
            SpecialKey(keyEquivalent: "\r", displayName: "↩", accessibilityName: "Return")
        case kVK_Tab:
            SpecialKey(keyEquivalent: "\t", displayName: "⇥", accessibilityName: "Tab")
        case kVK_Space:
            SpecialKey(keyEquivalent: " ", displayName: "Space", accessibilityName: "Space")
        case kVK_Delete:
            SpecialKey(keyEquivalent: "\u{8}", displayName: "⌫", accessibilityName: "Delete")
        case kVK_ForwardDelete:
            functionKey(0xF728, displayName: "⌦", accessibilityName: "Forward Delete")
        case kVK_Escape:
            SpecialKey(keyEquivalent: "\u{1b}", displayName: "⎋", accessibilityName: "Escape")
        case kVK_Home:
            functionKey(0xF729, displayName: "↖", accessibilityName: "Home")
        case kVK_End:
            functionKey(0xF72B, displayName: "↘", accessibilityName: "End")
        case kVK_PageUp:
            functionKey(0xF72C, displayName: "⇞", accessibilityName: "Page Up")
        case kVK_PageDown:
            functionKey(0xF72D, displayName: "⇟", accessibilityName: "Page Down")
        case kVK_LeftArrow:
            functionKey(0xF702, displayName: "←", accessibilityName: "Left Arrow")
        case kVK_RightArrow:
            functionKey(0xF703, displayName: "→", accessibilityName: "Right Arrow")
        case kVK_DownArrow:
            functionKey(0xF701, displayName: "↓", accessibilityName: "Down Arrow")
        case kVK_UpArrow:
            functionKey(0xF700, displayName: "↑", accessibilityName: "Up Arrow")
        case kVK_F1: functionKey(0xF704, displayName: "F1", accessibilityName: "F1")
        case kVK_F2: functionKey(0xF705, displayName: "F2", accessibilityName: "F2")
        case kVK_F3: functionKey(0xF706, displayName: "F3", accessibilityName: "F3")
        case kVK_F4: functionKey(0xF707, displayName: "F4", accessibilityName: "F4")
        case kVK_F5: functionKey(0xF708, displayName: "F5", accessibilityName: "F5")
        case kVK_F6: functionKey(0xF709, displayName: "F6", accessibilityName: "F6")
        case kVK_F7: functionKey(0xF70A, displayName: "F7", accessibilityName: "F7")
        case kVK_F8: functionKey(0xF70B, displayName: "F8", accessibilityName: "F8")
        case kVK_F9: functionKey(0xF70C, displayName: "F9", accessibilityName: "F9")
        case kVK_F10: functionKey(0xF70D, displayName: "F10", accessibilityName: "F10")
        case kVK_F11: functionKey(0xF70E, displayName: "F11", accessibilityName: "F11")
        case kVK_F12: functionKey(0xF70F, displayName: "F12", accessibilityName: "F12")
        case kVK_F13: functionKey(0xF710, displayName: "F13", accessibilityName: "F13")
        case kVK_F14: functionKey(0xF711, displayName: "F14", accessibilityName: "F14")
        case kVK_F15: functionKey(0xF712, displayName: "F15", accessibilityName: "F15")
        case kVK_F16: functionKey(0xF713, displayName: "F16", accessibilityName: "F16")
        case kVK_F17: functionKey(0xF714, displayName: "F17", accessibilityName: "F17")
        case kVK_F18: functionKey(0xF715, displayName: "F18", accessibilityName: "F18")
        case kVK_F19: functionKey(0xF716, displayName: "F19", accessibilityName: "F19")
        case kVK_F20: functionKey(0xF717, displayName: "F20", accessibilityName: "F20")
        default:
            nil
        }
    }

    private static func functionKey(
        _ scalarValue: UInt32,
        displayName: String,
        accessibilityName: String
    ) -> SpecialKey? {
        guard let scalar = UnicodeScalar(scalarValue) else { return nil }
        return SpecialKey(
            keyEquivalent: String(scalar),
            displayName: displayName,
            accessibilityName: accessibilityName
        )
    }
}
