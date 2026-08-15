import Carbon

@MainActor
final class GlobalHotKey {
    struct Registration {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let commandTitle: String
        let shortcutGlyphs: String
        let shortcutAccessibilityName: String
        let displayName: String
        let action: () -> Void

        static func render(action: @escaping () -> Void) -> Registration {
            Registration(
                id: 1,
                keyCode: UInt32(kVK_ANSI_X),
                modifiers: UInt32(cmdKey | controlKey),
                commandTitle: L10n.text(
                    "menu.render",
                    defaultValue: "Render Clipboard as Image"
                ),
                shortcutGlyphs: "⌃⌘X",
                shortcutAccessibilityName: L10n.text(
                    "shortcut.control_command_x",
                    defaultValue: "Control-Command-X"
                ),
                displayName: L10n.text(
                    "hotkey.render",
                    defaultValue: "Render (Control-Command-X)"
                ),
                action: action
            )
        }

        static func showLastRender(action: @escaping () -> Void) -> Registration {
            Registration(
                id: 2,
                keyCode: UInt32(kVK_ANSI_Z),
                modifiers: UInt32(cmdKey | controlKey),
                commandTitle: L10n.text(
                    "menu.show_last_render",
                    defaultValue: "Show Last Render"
                ),
                shortcutGlyphs: "⌃⌘Z",
                shortcutAccessibilityName: L10n.text(
                    "shortcut.control_command_z",
                    defaultValue: "Control-Command-Z"
                ),
                displayName: L10n.text(
                    "hotkey.show_last_render",
                    defaultValue: "Show Last Render (Control-Command-Z)"
                ),
                action: action
            )
        }
    }

    private var hotKeys: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private let actions: [UInt32: () -> Void]
    private(set) var failedRegistrations: [Registration] = []

    init(registrations: [Registration]) {
        actions = Dictionary(uniqueKeysWithValues: registrations.map { ($0.id, $0.action) })

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            failedRegistrations = registrations
            return
        }

        for registration in registrations {
            var hotKey: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: globalHotKeySignature, id: registration.id)
            if RegisterEventHotKey(
                registration.keyCode,
                registration.modifiers,
                identifier,
                GetApplicationEventTarget(),
                0,
                &hotKey
            ) == noErr {
                hotKeys.append(hotKey)
            } else {
                failedRegistrations.append(registration)
            }
        }
    }

    fileprivate func invoke(identifier: UInt32) {
        actions[identifier]?()
    }
}

private let globalHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr, identifier.signature == globalHotKeySignature else {
        return OSStatus(eventNotHandledErr)
    }
    let instance = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in instance.invoke(identifier: identifier.id) }
    return noErr
}

private let globalHotKeySignature = OSType(0x4D44504E) // MDPN
