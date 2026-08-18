import AppKit
import Carbon
import Foundation

struct GlobalShortcutKey: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt32
    let keyEquivalent: String
    let displayName: String
    let accessibilityName: String

    init?(
        keyCode: UInt32,
        keyEquivalent: String,
        displayName: String,
        accessibilityName: String
    ) {
        guard Self.valuesAreValid(
            keyCode: keyCode,
            keyEquivalent: keyEquivalent,
            displayName: displayName,
            accessibilityName: accessibilityName
        ) else { return nil }
        self.keyCode = keyCode
        self.keyEquivalent = keyEquivalent
        self.displayName = displayName
        self.accessibilityName = accessibilityName
    }

    var isValid: Bool {
        Self.valuesAreValid(
            keyCode: keyCode,
            keyEquivalent: keyEquivalent,
            displayName: displayName,
            accessibilityName: accessibilityName
        )
    }

    static let x = GlobalShortcutKey(
        keyCode: UInt32(kVK_ANSI_X),
        keyEquivalent: "x",
        displayName: "X",
        accessibilityName: "X"
    )!

    static let z = GlobalShortcutKey(
        keyCode: UInt32(kVK_ANSI_Z),
        keyEquivalent: "z",
        displayName: "Z",
        accessibilityName: "Z"
    )!

    private static func valuesAreValid(
        keyCode: UInt32,
        keyEquivalent: String,
        displayName: String,
        accessibilityName: String
    ) -> Bool {
        keyCode <= UInt32(UInt16.max)
            && keyEquivalent.count == 1
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !accessibilityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct GlobalShortcut: Codable, Equatable, Hashable, Sendable {
    struct Modifiers: OptionSet, Codable, Equatable, Hashable, Sendable {
        let rawValue: UInt32

        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        static let supported: Modifiers = [.control, .option, .shift, .command]
        static let primary: Modifiers = [.control, .option, .command]
    }

    let key: GlobalShortcutKey
    let modifiers: Modifiers

    init?(key: GlobalShortcutKey, modifiers: Modifiers) {
        guard Self.valuesAreValid(key: key, modifiers: modifiers) else { return nil }
        self.key = key
        self.modifiers = modifiers
    }

    var isValid: Bool {
        Self.valuesAreValid(key: key, modifiers: modifiers)
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        var value: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { value.insert(.control) }
        if modifiers.contains(.option) { value.insert(.option) }
        if modifiers.contains(.shift) { value.insert(.shift) }
        if modifiers.contains(.command) { value.insert(.command) }
        return value
    }

    var glyphs: String {
        presentationKeys.joined()
    }

    var presentationKeys: [String] {
        modifierPresentation.map(\.glyph) + [key.displayName]
    }

    var accessibilityName: String {
        (modifierPresentation.map(\.accessibilityName) + [key.accessibilityName])
            .joined(separator: "-")
    }

    func hasSameRegistration(as other: GlobalShortcut) -> Bool {
        key.keyCode == other.key.keyCode && modifiers == other.modifiers
    }

    static let defaultRender = GlobalShortcut(
        key: .x,
        modifiers: [.control, .command]
    )!

    static let defaultShowLastRender = GlobalShortcut(
        key: .z,
        modifiers: [.control, .command]
    )!

    private var modifierPresentation: [(glyph: String, accessibilityName: String)] {
        var values: [(String, String)] = []
        if modifiers.contains(.control) { values.append(("⌃", "Control")) }
        if modifiers.contains(.option) { values.append(("⌥", "Option")) }
        if modifiers.contains(.shift) { values.append(("⇧", "Shift")) }
        if modifiers.contains(.command) { values.append(("⌘", "Command")) }
        return values
    }

    private static func valuesAreValid(
        key: GlobalShortcutKey,
        modifiers: Modifiers
    ) -> Bool {
        key.isValid
            && !modifiers.intersection(.primary).isEmpty
            && modifiers.subtracting(.supported).isEmpty
    }
}

struct GlobalShortcutConfiguration: Codable, Equatable, Sendable {
    var render: GlobalShortcut
    var showLastRender: GlobalShortcut

    static let `default` = GlobalShortcutConfiguration(
        render: .defaultRender,
        showLastRender: .defaultShowLastRender
    )

    var isValid: Bool {
        render.isValid
            && showLastRender.isValid
            && !render.hasSameRegistration(as: showLastRender)
    }

    var conflictingCommands: Set<GlobalShortcutCommand> {
        guard render.hasSameRegistration(as: showLastRender) else { return [] }
        return [.render, .showLastRender]
    }

    subscript(command: GlobalShortcutCommand) -> GlobalShortcut {
        get {
            switch command {
            case .render:
                render
            case .showLastRender:
                showLastRender
            }
        }
        set {
            switch command {
            case .render:
                render = newValue
            case .showLastRender:
                showLastRender = newValue
            }
        }
    }
}

struct GlobalShortcutPreference {
    static let defaultsKey = "GlobalShortcuts.configuration.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var configuration: GlobalShortcutConfiguration {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let configuration = try? decoder.decode(
                  GlobalShortcutConfiguration.self,
                  from: data
              ), configuration.isValid else {
            return .default
        }
        return configuration
    }

    @discardableResult
    func save(_ configuration: GlobalShortcutConfiguration) -> Bool {
        guard configuration.isValid,
              let data = try? encoder.encode(configuration) else { return false }
        defaults.set(data, forKey: Self.defaultsKey)
        return true
    }

    func restoreDefaults() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
