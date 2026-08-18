import AppKit
import Combine

enum ShortcutSettingsFeedback: Equatable {
    case missingPrimaryModifier
    case unsupportedKey
    case duplicate
    case saveFailed
    case registrationUnavailable(Set<GlobalShortcutCommand>)
    case restoredDefaults
}

@MainActor
final class ShortcutSettingsModel: ObservableObject {
    typealias ApplyConfiguration = (GlobalShortcutConfiguration) -> Set<UInt32>
    typealias RecordingLifecycleAction = () -> Void

    @Published private(set) var configuration: GlobalShortcutConfiguration
    @Published private(set) var failedRegistrationIDs: Set<UInt32>
    @Published private(set) var recordingCommand: GlobalShortcutCommand?
    @Published private(set) var feedback: ShortcutSettingsFeedback?

    private let preference: GlobalShortcutPreference
    private let onRecordingBegan: RecordingLifecycleAction
    private let onRecordingCancelled: RecordingLifecycleAction
    private let applyConfiguration: ApplyConfiguration

    init(
        preference: GlobalShortcutPreference = GlobalShortcutPreference(),
        configuration: GlobalShortcutConfiguration? = nil,
        failedRegistrationIDs: Set<UInt32> = [],
        onRecordingBegan: @escaping RecordingLifecycleAction = {},
        onRecordingCancelled: @escaping RecordingLifecycleAction = {},
        applyConfiguration: @escaping ApplyConfiguration
    ) {
        let configuration = configuration ?? preference.configuration
        precondition(configuration.isValid)
        self.preference = preference
        self.configuration = configuration
        self.failedRegistrationIDs = failedRegistrationIDs
        self.onRecordingBegan = onRecordingBegan
        self.onRecordingCancelled = onRecordingCancelled
        self.applyConfiguration = applyConfiguration
    }

    func refresh(
        configuration: GlobalShortcutConfiguration,
        failedRegistrationIDs: Set<UInt32>
    ) {
        precondition(configuration.isValid)
        let wasRecording = recordingCommand != nil
        self.configuration = configuration
        self.failedRegistrationIDs = failedRegistrationIDs
        recordingCommand = nil
        feedback = registrationFeedback(for: failedRegistrationIDs)
        if wasRecording {
            onRecordingCancelled()
        }
    }

    func beginRecording(_ command: GlobalShortcutCommand) {
        let wasRecording = recordingCommand != nil
        recordingCommand = command
        feedback = nil
        if !wasRecording {
            onRecordingBegan()
        }
    }

    func cancelRecording() {
        let wasRecording = recordingCommand != nil
        recordingCommand = nil
        feedback = nil
        if wasRecording {
            onRecordingCancelled()
        }
    }

    @discardableResult
    func capture(_ event: NSEvent, for command: GlobalShortcutCommand) -> Bool {
        switch GlobalShortcutCapture.shortcut(from: event) {
        case let .success(shortcut):
            return setShortcut(shortcut, for: command)
        case .failure(.missingPrimaryModifier):
            feedback = .missingPrimaryModifier
        case .failure(.unsupportedKey):
            feedback = .unsupportedKey
        }
        return false
    }

    @discardableResult
    func setShortcut(
        _ shortcut: GlobalShortcut,
        for command: GlobalShortcutCommand
    ) -> Bool {
        var candidate = configuration
        candidate[command] = shortcut
        guard candidate.isValid else {
            feedback = .duplicate
            return false
        }
        guard preference.save(candidate) else {
            feedback = .saveFailed
            return false
        }

        configuration = candidate
        recordingCommand = nil
        failedRegistrationIDs = applyConfiguration(candidate)
        feedback = registrationFeedback(for: failedRegistrationIDs)
        return true
    }

    func restoreDefaults() {
        preference.restoreDefaults()
        configuration = .default
        recordingCommand = nil
        failedRegistrationIDs = applyConfiguration(.default)
        feedback = registrationFeedback(for: failedRegistrationIDs) ?? .restoredDefaults
    }

    private func registrationFeedback(
        for failedRegistrationIDs: Set<UInt32>
    ) -> ShortcutSettingsFeedback? {
        let commands = Set(GlobalShortcutCommand.allCases.filter {
            failedRegistrationIDs.contains($0.rawValue)
        })
        return commands.isEmpty ? nil : .registrationUnavailable(commands)
    }
}
