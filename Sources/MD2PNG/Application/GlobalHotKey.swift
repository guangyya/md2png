import Carbon

enum GlobalShortcutCommand: UInt32, CaseIterable, Codable, Sendable {
    case render = 1
    case showLastRender = 2
}

@MainActor
struct GlobalShortcutRouter {
    private let verify: (GlobalShortcutCommand) -> Bool
    private let perform: (GlobalShortcutCommand) -> Void

    init(
        verify: @escaping (GlobalShortcutCommand) -> Bool,
        perform: @escaping (GlobalShortcutCommand) -> Void
    ) {
        self.verify = verify
        self.perform = perform
    }

    func handle(_ command: GlobalShortcutCommand) {
        guard !verify(command) else { return }
        perform(command)
    }
}

@MainActor
protocol GlobalHotKeySession: AnyObject {
    var failedRegistrationIDs: Set<UInt32> { get }
    func invalidate()
}

@MainActor
final class GlobalHotKey: GlobalHotKeySession {
    struct Registration {
        let id: UInt32
        let shortcut: GlobalShortcut
        let commandTitle: String
        let displayName: String
        let action: () -> Void

        var keyCode: UInt32 { shortcut.key.keyCode }
        var modifiers: UInt32 { shortcut.carbonModifiers }
        var shortcutGlyphs: String { shortcut.glyphs }
        var shortcutAccessibilityName: String { shortcut.accessibilityName }

        static func render(
            shortcut: GlobalShortcut = .defaultRender,
            localizationBundle: Bundle? = nil,
            action: @escaping () -> Void
        ) -> Registration {
            let commandTitle = L10n.text(
                "menu.render",
                defaultValue: "Render Clipboard as Image",
                bundle: localizationBundle
            )
            let displayTitle = L10n.text(
                "hotkey.render_title",
                defaultValue: "Render",
                bundle: localizationBundle
            )
            return Registration(
                id: GlobalShortcutCommand.render.rawValue,
                shortcut: shortcut,
                commandTitle: commandTitle,
                displayName: L10n.format(
                    "hotkey.command_format",
                    defaultValue: "%1$@ (%2$@)",
                    bundle: localizationBundle,
                    displayTitle,
                    shortcut.accessibilityName
                ),
                action: action
            )
        }

        static func showLastRender(
            shortcut: GlobalShortcut = .defaultShowLastRender,
            localizationBundle: Bundle? = nil,
            action: @escaping () -> Void
        ) -> Registration {
            let commandTitle = L10n.text(
                "menu.show_last_render",
                defaultValue: "Show Last Render",
                bundle: localizationBundle
            )
            let displayTitle = L10n.text(
                "hotkey.show_last_render_title",
                defaultValue: "Show Last Render",
                bundle: localizationBundle
            )
            return Registration(
                id: GlobalShortcutCommand.showLastRender.rawValue,
                shortcut: shortcut,
                commandTitle: commandTitle,
                displayName: L10n.format(
                    "hotkey.command_format",
                    defaultValue: "%1$@ (%2$@)",
                    bundle: localizationBundle,
                    displayTitle,
                    shortcut.accessibilityName
                ),
                action: action
            )
        }
    }

    private var hotKeys: [EventHotKeyRef?] = []
    private var eventHandler: EventHandlerRef?
    private let actions: [UInt32: () -> Void]
    private(set) var failedRegistrations: [Registration] = []
    private(set) var isInvalidated = false

    var failedRegistrationIDs: Set<UInt32> {
        Set(failedRegistrations.map(\.id))
    }

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

    isolated deinit {
        invalidate()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        for hotKey in hotKeys {
            if let hotKey {
                UnregisterEventHotKey(hotKey)
            }
        }
        hotKeys.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    fileprivate func invoke(identifier: UInt32) {
        guard !isInvalidated else { return }
        actions[identifier]?()
    }
}

@MainActor
final class GlobalHotKeyRegistrar {
    typealias SessionFactory = ([GlobalHotKey.Registration]) -> any GlobalHotKeySession

    private let makeSession: SessionFactory
    private var session: (any GlobalHotKeySession)?

    init(
        makeSession: @escaping SessionFactory = { registrations in
            GlobalHotKey(registrations: registrations)
        }
    ) {
        self.makeSession = makeSession
    }

    isolated deinit {
        session?.invalidate()
    }

    @discardableResult
    func replace(
        registrations: [GlobalHotKey.Registration]
    ) -> Set<UInt32> {
        session?.invalidate()
        let replacement = makeSession(registrations)
        session = replacement
        return replacement.failedRegistrationIDs
    }

    func invalidate() {
        session?.invalidate()
        session = nil
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
