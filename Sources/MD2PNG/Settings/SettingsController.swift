import AppKit
import SwiftUI

@MainActor
final class SettingsController: NSWindowController, NSWindowDelegate {
    private let copy: SettingsCopy
    private let contentModel: ShortcutSettingsModel
    private let launchAtLoginModel: LaunchAtLoginSettingsModel
    private let renderCornerModel: RenderCornerSettingsModel
    private let onVisibilityChange: (Bool) -> Void

#if DEBUG
    var displayedConfiguration: GlobalShortcutConfiguration {
        contentModel.configuration
    }
    var displayedFeedback: ShortcutSettingsFeedback? {
        contentModel.feedback
    }
    var displayedRecordingCommand: GlobalShortcutCommand? {
        contentModel.recordingCommand
    }
    var displayedLaunchAtLoginStatus: LaunchAtLoginStatus {
        launchAtLoginModel.status
    }
    var displayedLaunchAtLoginIsEnabled: Bool {
        launchAtLoginModel.isEnabled
    }
    var displayedLaunchAtLoginError: String? {
        launchAtLoginModel.errorMessage
    }
    var displayedRoundedCornersEnabled: Bool {
        renderCornerModel.isEnabled
    }
    var displayedContentSize: NSSize {
        window?.contentView?.bounds.size ?? .zero
    }
    var usesSwiftUIHostingBoundary: Bool {
        window?.contentViewController is NSHostingController<SettingsContentView>
    }
#endif

    init(
        preference: GlobalShortcutPreference = GlobalShortcutPreference(),
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController(),
        renderCornerPreference: RenderCornerPreference = RenderCornerPreference(),
        localizationBundle: Bundle? = nil,
        onApply: @escaping ShortcutSettingsModel.ApplyConfiguration,
        onRecordingBegan: @escaping ShortcutSettingsModel.RecordingLifecycleAction = {},
        onRecordingCancelled: @escaping ShortcutSettingsModel.RecordingLifecycleAction = {},
        onLaunchAtLoginChange: @escaping () -> Void = {},
        onVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        copy = SettingsCopy(localizationBundle: localizationBundle)
        contentModel = ShortcutSettingsModel(
            preference: preference,
            onRecordingBegan: onRecordingBegan,
            onRecordingCancelled: onRecordingCancelled,
            applyConfiguration: onApply
        )
        launchAtLoginModel = LaunchAtLoginSettingsModel(
            controller: launchAtLoginController,
            onStatusChange: onLaunchAtLoginChange
        )
        renderCornerModel = RenderCornerSettingsModel(
            preference: renderCornerPreference
        )
        self.onVisibilityChange = onVisibilityChange
        let window = AppWindow(
            contentRect: NSRect(origin: .zero, size: SettingsLayout.windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = copy.windowTitle
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.collectionBehavior.insert(.moveToActiveSpace)
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: SettingsContentView(
                model: contentModel,
                launchAtLoginModel: launchAtLoginModel,
                renderCornerModel: renderCornerModel,
                copy: copy
            )
        )
        window.setContentSize(SettingsLayout.windowSize)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        configuration: GlobalShortcutConfiguration,
        failedRegistrationIDs: Set<UInt32>
    ) {
        contentModel.refresh(
            configuration: configuration,
            failedRegistrationIDs: failedRegistrationIDs
        )
        launchAtLoginModel.refresh()
        renderCornerModel.refresh()
        if window?.isVisible != true {
            onVisibilityChange(true)
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        contentModel.cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        contentModel.cancelRecording()
        onVisibilityChange(false)
    }

    func refreshLaunchAtLogin() {
        launchAtLoginModel.refresh()
    }

#if DEBUG
    @discardableResult
    func captureForTesting(
        _ event: NSEvent,
        command: GlobalShortcutCommand
    ) -> Bool {
        contentModel.capture(event, for: command)
    }

    func restoreDefaultsForTesting() {
        contentModel.restoreDefaults()
    }

    func beginRecordingForTesting(_ command: GlobalShortcutCommand) {
        contentModel.beginRecording(command)
    }

    func cancelRecordingForTesting() {
        contentModel.cancelRecording()
    }

    func setLaunchAtLoginForTesting(_ isEnabled: Bool) {
        launchAtLoginModel.setEnabled(isEnabled)
    }

    func setRoundedCornersForTesting(_ isEnabled: Bool) {
        renderCornerModel.setEnabled(isEnabled)
    }

    func performLaunchAtLoginPrimaryActionForTesting() {
        launchAtLoginModel.performPrimaryAction()
    }

    func openLaunchAtLoginSystemSettingsForTesting() {
        launchAtLoginModel.openSystemSettings()
    }
#endif
}
