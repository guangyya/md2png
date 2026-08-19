import AppKit

final class WelcomePreference {
    static let defaultsKey = "welcome.completed"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldShowOnLaunch: Bool {
        !defaults.bool(forKey: Self.defaultsKey)
    }

    func markCompleted() {
        defaults.set(true, forKey: Self.defaultsKey)
    }
}

struct WelcomeShortcutStatus: Identifiable, Equatable {
    let id: UInt32
    let title: String
    let shortcutGlyphs: String
    let shortcutKeys: [String]
    let shortcutAccessibilityName: String
    let isRegistered: Bool
    private(set) var isVerified: Bool
    private(set) var verificationCount: Int

    init(
        registration: GlobalHotKey.Registration,
        failedRegistrationIDs: Set<UInt32>
    ) {
        id = registration.id
        title = registration.commandTitle
        shortcutGlyphs = registration.shortcutGlyphs
        shortcutKeys = registration.shortcut.presentationKeys
        shortcutAccessibilityName = registration.shortcutAccessibilityName
        isRegistered = !failedRegistrationIDs.contains(registration.id)
        isVerified = false
        verificationCount = 0
    }

    init(
        id: UInt32,
        title: String,
        shortcutGlyphs: String,
        shortcutKeys: [String]? = nil,
        shortcutAccessibilityName: String,
        isRegistered: Bool,
        isVerified: Bool = false
    ) {
        self.id = id
        self.title = title
        self.shortcutGlyphs = shortcutGlyphs
        self.shortcutKeys = shortcutKeys ?? shortcutGlyphs.map(String.init)
        self.shortcutAccessibilityName = shortcutAccessibilityName
        self.isRegistered = isRegistered
        self.isVerified = isRegistered && isVerified
        verificationCount = 0
    }

    mutating func resetVerification() {
        isVerified = false
        verificationCount = 0
    }

    @discardableResult
    mutating func verify() -> Bool {
        guard isRegistered else { return false }
        isVerified = true
        verificationCount += 1
        return true
    }
}

struct WelcomeWindowPlacement {
    static func centeredOrigin(
        windowSize: NSSize,
        visibleFrame: NSRect
    ) -> NSPoint {
        let centeredX = visibleFrame.midX - windowSize.width / 2
        let centeredY = visibleFrame.midY - windowSize.height / 2
        return NSPoint(
            x: clampedOrigin(
                centeredX,
                minimum: visibleFrame.minX,
                maximum: visibleFrame.maxX - windowSize.width
            ),
            y: clampedOrigin(
                centeredY,
                minimum: visibleFrame.minY,
                maximum: visibleFrame.maxY - windowSize.height
            )
        )
    }

    private static func clampedOrigin(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        guard maximum >= minimum else { return minimum }
        return min(max(value, minimum), maximum)
    }
}

enum WelcomeLayout {
    static let preferredContentSize = NSSize(width: 560, height: 570)
    static let screenInset: CGFloat = 12
    static let statusColumnMinimumWidth: CGFloat = 88

    static func contentSize(maximumContentSize: NSSize) -> NSSize {
        NSSize(
            width: max(1, min(preferredContentSize.width, maximumContentSize.width)),
            height: max(1, min(preferredContentSize.height, maximumContentSize.height))
        )
    }
}

struct WelcomeCopy {
    let windowTitle: String
    let title: String
    let subtitle: String
    let copyStepTitle: String
    let copyStepDetail: String
    let copyStepCompletionDetail: String
    let renderStepTitle: String
    let renderStepDetail: String
    let renderStepCompletionDetail: String
    let pasteStepTitle: String
    let pasteStepDetail: String
    let pasteStepCompletionDetail: String
    let shortcutsTitle: String
    let shortcutVerificationHelp: String
    let shortcutReady: String
    let shortcutDetected: String
    let shortcutVerified: String
    let shortcutUnavailable: String
    let shortcutConflictHelp: String
    let shortcutVerifiedAnnouncementFormat: String
    let launchAtLoginTitle: String
    let launchAtLoginOptional: String
    let launchAtLoginOn: String
    let launchAtLoginOff: String
    let launchAtLoginOpenSettings: String
    let launchAtLoginUnavailable: String
    let launchAtLoginApprovalHelp: String
    let privacyNote: String
    let reopenHint: String
    let trySample: String
    let trySampleHelp: String
    let replayDemo: String
    let done: String

    init(localizationBundle: Bundle? = nil) {
        windowTitle = L10n.text(
            "welcome.window_title",
            defaultValue: "Welcome to md2png",
            bundle: localizationBundle
        )
        title = L10n.text(
            "welcome.title",
            defaultValue: "Turn Markdown into a polished PNG",
            bundle: localizationBundle
        )
        subtitle = L10n.text(
            "welcome.subtitle",
            defaultValue: "A private, local workflow in three simple steps.",
            bundle: localizationBundle
        )
        copyStepTitle = L10n.text(
            "welcome.step.copy.title",
            defaultValue: "Copy Markdown",
            bundle: localizationBundle
        )
        copyStepDetail = L10n.text(
            "welcome.step.copy.detail",
            defaultValue: "Copy Markdown text in any app.",
            bundle: localizationBundle
        )
        copyStepCompletionDetail = L10n.text(
            "welcome.step.copy.completion_detail",
            defaultValue: "Copy in any app",
            bundle: localizationBundle
        )
        renderStepTitle = L10n.text(
            "welcome.step.render.title",
            defaultValue: "Render it",
            bundle: localizationBundle
        )
        renderStepDetail = L10n.text(
            "welcome.step.render.detail",
            defaultValue: "Use the global shortcut or choose Render Clipboard as Image from the menu bar.",
            bundle: localizationBundle
        )
        renderStepCompletionDetail = L10n.text(
            "welcome.step.render.completion_detail",
            defaultValue: "Render locally",
            bundle: localizationBundle
        )
        pasteStepTitle = L10n.text(
            "welcome.step.paste.title",
            defaultValue: "Paste the PNG",
            bundle: localizationBundle
        )
        pasteStepDetail = L10n.text(
            "welcome.step.paste.detail",
            defaultValue: "Press Command-V, review the image, and send it yourself.",
            bundle: localizationBundle
        )
        pasteStepCompletionDetail = L10n.text(
            "welcome.step.paste.completion_detail",
            defaultValue: "Review, then send",
            bundle: localizationBundle
        )
        shortcutsTitle = L10n.text(
            "welcome.shortcuts",
            defaultValue: "Global shortcuts",
            bundle: localizationBundle
        )
        shortcutVerificationHelp = L10n.text(
            "welcome.shortcut_verification_help",
            defaultValue: "Press a shortcut here to test it without running the command.",
            bundle: localizationBundle
        )
        shortcutReady = L10n.text(
            "welcome.shortcut_ready",
            defaultValue: "Ready",
            bundle: localizationBundle
        )
        shortcutDetected = L10n.text(
            "welcome.shortcut_detected",
            defaultValue: "Detected",
            bundle: localizationBundle
        )
        shortcutVerified = L10n.text(
            "welcome.shortcut_verified",
            defaultValue: "Works",
            bundle: localizationBundle
        )
        shortcutUnavailable = L10n.text(
            "welcome.shortcut_unavailable",
            defaultValue: "In Use",
            bundle: localizationBundle
        )
        shortcutConflictHelp = L10n.text(
            "welcome.shortcut_conflict_help",
            defaultValue: "Another app is using a shortcut. Every action remains available from the md2png menu.",
            bundle: localizationBundle
        )
        shortcutVerifiedAnnouncementFormat = L10n.text(
            "welcome.shortcut_verified_announcement",
            defaultValue: "%@ shortcut works.",
            bundle: localizationBundle
        )
        launchAtLoginTitle = L10n.text(
            "welcome.launch_at_login.title",
            defaultValue: "Launch at Login",
            bundle: localizationBundle
        )
        launchAtLoginOptional = L10n.text(
            "welcome.launch_at_login.optional",
            defaultValue: "Optional",
            bundle: localizationBundle
        )
        launchAtLoginOn = L10n.text(
            "welcome.launch_at_login.on",
            defaultValue: "On",
            bundle: localizationBundle
        )
        launchAtLoginOff = L10n.text(
            "welcome.launch_at_login.off",
            defaultValue: "Off",
            bundle: localizationBundle
        )
        launchAtLoginOpenSettings = L10n.text(
            "welcome.launch_at_login.open_settings",
            defaultValue: "Open Settings…",
            bundle: localizationBundle
        )
        launchAtLoginUnavailable = L10n.text(
            "welcome.launch_at_login.unavailable",
            defaultValue: "Unavailable",
            bundle: localizationBundle
        )
        launchAtLoginApprovalHelp = L10n.text(
            "welcome.launch_at_login.approval_help",
            defaultValue: "Approval is required in Login Items.",
            bundle: localizationBundle
        )
        privacyNote = L10n.text(
            "welcome.privacy_note",
            defaultValue: "Private and local. Nothing is uploaded automatically.",
            bundle: localizationBundle
        )
        reopenHint = L10n.text(
            "welcome.reopen_hint",
            defaultValue: "Reopen from Show Welcome in the menu.",
            bundle: localizationBundle
        )
        trySample = L10n.text(
            "welcome.try_sample",
            defaultValue: "Try an Example",
            bundle: localizationBundle
        )
        trySampleHelp = L10n.text(
            "welcome.try_sample_help",
            defaultValue: "Choose a bundled example to try.",
            bundle: localizationBundle
        )
        replayDemo = L10n.text(
            "welcome.replay_demo",
            defaultValue: "Replay workflow demo",
            bundle: localizationBundle
        )
        done = L10n.text(
            "welcome.done",
            defaultValue: "Done",
            bundle: localizationBundle
        )
    }
}
