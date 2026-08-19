import AppKit

enum SettingsLayout {
    static let windowSize = NSSize(width: 520, height: 486)
    static let generalRowHeight: CGFloat = 60
    static let rowHeight: CGFloat = 56
    static let feedbackHeight: CGFloat = 44
}

struct SettingsCopy {
    let windowTitle: String
    let generalTitle: String
    let launchAtLogin: String
    let launchAtLoginDetail: String
    let launchAtLoginApproval: String
    let launchAtLoginUnavailable: String
    let launchAtLoginOn: String
    let launchAtLoginOff: String
    let openSystemSettings: String
    let outputTitle: String
    let roundedCorners: String
    let roundedCornersDetail: String
    let title: String
    let subtitle: String
    let render: String
    let showLastRender: String
    let recording: String
    let recordHelp: String
    let unavailable: String
    let idleHelp: String
    let restoreDefaults: String
    let localizationBundle: Bundle?

    init(localizationBundle: Bundle? = nil) {
        self.localizationBundle = localizationBundle
        windowTitle = L10n.text(
            "settings.window_title",
            defaultValue: "Settings",
            bundle: localizationBundle
        )
        generalTitle = L10n.text(
            "settings.general_title",
            defaultValue: "General",
            bundle: localizationBundle
        )
        launchAtLogin = L10n.text(
            "settings.launch_at_login",
            defaultValue: "Launch at Login",
            bundle: localizationBundle
        )
        launchAtLoginDetail = L10n.text(
            "settings.launch_at_login_detail",
            defaultValue: "Start md2png automatically when you log in.",
            bundle: localizationBundle
        )
        launchAtLoginApproval = L10n.text(
            "settings.launch_at_login_approval",
            defaultValue: "Approval is required in Login Items.",
            bundle: localizationBundle
        )
        launchAtLoginUnavailable = L10n.text(
            "settings.launch_at_login_unavailable",
            defaultValue: "This setting is unavailable on this Mac.",
            bundle: localizationBundle
        )
        launchAtLoginOn = L10n.text(
            "settings.launch_at_login_on",
            defaultValue: "On",
            bundle: localizationBundle
        )
        launchAtLoginOff = L10n.text(
            "settings.launch_at_login_off",
            defaultValue: "Off",
            bundle: localizationBundle
        )
        openSystemSettings = L10n.text(
            "settings.open_system_settings",
            defaultValue: "Open System Settings…",
            bundle: localizationBundle
        )
        outputTitle = L10n.text(
            "settings.output_title",
            defaultValue: "PNG Output",
            bundle: localizationBundle
        )
        roundedCorners = L10n.text(
            "settings.rounded_corners",
            defaultValue: "Rounded Corners",
            bundle: localizationBundle
        )
        roundedCornersDetail = L10n.text(
            "settings.rounded_corners_detail",
            defaultValue: "Make the corners of newly rendered PNGs transparent.",
            bundle: localizationBundle
        )
        title = L10n.text(
            "settings.shortcuts_title",
            defaultValue: "Keyboard Shortcuts",
            bundle: localizationBundle
        )
        subtitle = L10n.text(
            "settings.shortcuts_subtitle",
            defaultValue: "Click a shortcut, then press a new key combination.",
            bundle: localizationBundle
        )
        render = L10n.text(
            "hotkey.render_title",
            defaultValue: "Render",
            bundle: localizationBundle
        )
        showLastRender = L10n.text(
            "hotkey.show_last_render_title",
            defaultValue: "Show Last Render",
            bundle: localizationBundle
        )
        recording = L10n.text(
            "settings.recording",
            defaultValue: "Type shortcut…",
            bundle: localizationBundle
        )
        recordHelp = L10n.text(
            "settings.record_help",
            defaultValue: "Use Control, Option, or Command. Press Escape to cancel.",
            bundle: localizationBundle
        )
        unavailable = L10n.text(
            "settings.unavailable",
            defaultValue: "Unavailable",
            bundle: localizationBundle
        )
        idleHelp = L10n.text(
            "settings.idle_help",
            defaultValue: "Changes apply immediately. Menu commands always remain available.",
            bundle: localizationBundle
        )
        restoreDefaults = L10n.text(
            "settings.restore_defaults",
            defaultValue: "Restore Defaults",
            bundle: localizationBundle
        )
    }

    func commandTitle(_ command: GlobalShortcutCommand) -> String {
        switch command {
        case .render:
            render
        case .showLastRender:
            showLastRender
        }
    }

    func recorderAccessibilityLabel(_ command: GlobalShortcutCommand) -> String {
        L10n.format(
            "settings.recorder_accessibility_label",
            defaultValue: "%@ shortcut",
            bundle: localizationBundle,
            commandTitle(command)
        )
    }

    func feedbackText(_ feedback: ShortcutSettingsFeedback) -> String {
        switch feedback {
        case .missingPrimaryModifier:
            return L10n.text(
                "settings.feedback.missing_modifier",
                defaultValue: "Include Control, Option, or Command.",
                bundle: localizationBundle
            )
        case .unsupportedKey:
            return L10n.text(
                "settings.feedback.unsupported_key",
                defaultValue: "That key can’t be used. Try another combination.",
                bundle: localizationBundle
            )
        case .duplicate:
            return L10n.text(
                "settings.feedback.duplicate",
                defaultValue: "Choose a different shortcut for each command.",
                bundle: localizationBundle
            )
        case .saveFailed:
            return L10n.text(
                "settings.feedback.save_failed",
                defaultValue: "The shortcut couldn’t be saved. Try again.",
                bundle: localizationBundle
            )
        case let .registrationUnavailable(commands):
            if commands.count == 1, let command = commands.first {
                return L10n.format(
                    "settings.feedback.unavailable_command",
                    defaultValue: "%@ couldn’t be registered. Its menu command still works.",
                    bundle: localizationBundle,
                    commandTitle(command)
                )
            }
            return L10n.text(
                "settings.feedback.unavailable_multiple",
                defaultValue: "The shortcuts couldn’t be registered. "
                    + "Their menu commands still work.",
                bundle: localizationBundle
            )
        case .restoredDefaults:
            return L10n.text(
                "settings.feedback.restored",
                defaultValue: "Default shortcuts restored.",
                bundle: localizationBundle
            )
        }
    }
}
