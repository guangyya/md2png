import AppKit
import Foundation
import UniformTypeIdentifiers

enum AboutDiagnosticSaveState: Equatable {
    case idle
    case saving
    case saved
}

enum AboutDiagnosticSaveResult: Equatable {
    case saved
    case cancelled
    case failed
}

struct AboutDiagnosticLogSaveDependencies {
    let chooseDestination: @MainActor (
        _ parentWindow: NSWindow?,
        _ suggestedFileName: String
    ) async -> URL?
    let writeExport: @Sendable (
        _ export: DiagnosticExport,
        _ destinationURL: URL
    ) async throws -> Void
    let presentFailure: @MainActor (_ parentWindow: NSWindow?) -> Void

    @MainActor
    static func live() -> AboutDiagnosticLogSaveDependencies {
        AboutDiagnosticLogSaveDependencies(
            chooseDestination: { parentWindow, suggestedFileName in
                let panel = NSSavePanel()
                panel.title = L10n.text(
                    "about.diagnostic_logs_save_title",
                    defaultValue: "Save Diagnostic Logs"
                )
                panel.message = L10n.text(
                    "about.diagnostic_logs_save_message",
                    defaultValue: "Saves privacy-safe operational metadata only. Nothing is uploaded."
                )
                panel.nameFieldStringValue = suggestedFileName
                panel.allowedContentTypes = [.json]
                panel.canCreateDirectories = true
                panel.isExtensionHidden = false

                guard let parentWindow else {
                    return panel.runModal() == .OK ? panel.url : nil
                }
                return await withCheckedContinuation { continuation in
                    panel.beginSheetModal(for: parentWindow) { response in
                        continuation.resume(returning: response == .OK ? panel.url : nil)
                    }
                }
            },
            writeExport: { export, destinationURL in
                try await Task.detached(priority: .utility) {
                    try export.encodedData().write(
                        to: destinationURL,
                        options: .atomic
                    )
                }.value
            },
            presentFailure: { parentWindow in
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L10n.text(
                    "about.diagnostic_logs_save_failed_title",
                    defaultValue: "Couldn’t Save Diagnostic Logs"
                )
                alert.informativeText = L10n.text(
                    "about.diagnostic_logs_save_failed_message",
                    defaultValue: "The logs may be unavailable, or the selected location may not be writable. Choose another location and try again."
                )
                alert.addButton(withTitle: L10n.text("common.ok", defaultValue: "OK"))
                if let parentWindow {
                    alert.beginSheetModal(for: parentWindow)
                } else {
                    alert.runModal()
                }
            }
        )
    }
}

enum AboutDiagnosticSavePresentation {
    static func buttonTitle(for state: AboutDiagnosticSaveState) -> String {
        switch state {
        case .idle:
            return L10n.text(
                "about.save_diagnostic_logs",
                defaultValue: "Save Diagnostic Logs…"
            )
        case .saving:
            return L10n.text(
                "about.diagnostic_logs_saving",
                defaultValue: "Saving…"
            )
        case .saved:
            return L10n.text(
                "about.diagnostic_logs_saved",
                defaultValue: "Saved"
            )
        }
    }

    static func symbolName(for state: AboutDiagnosticSaveState) -> String {
        switch state {
        case .idle: "square.and.arrow.down"
        case .saving: "hourglass"
        case .saved: "checkmark.circle.fill"
        }
    }
}

extension DiagnosticExportWindow {
    var aboutMenuTitle: String {
        switch self {
        case .lastHour:
            return L10n.text(
                "about.diagnostic_logs_last_hour",
                defaultValue: "Last Hour"
            )
        case .last24Hours:
            return L10n.text(
                "about.diagnostic_logs_last_24_hours",
                defaultValue: "Last 24 Hours"
            )
        case .last7Days:
            return L10n.text(
                "about.diagnostic_logs_last_7_days",
                defaultValue: "Last 7 Days"
            )
        }
    }

    fileprivate var fileNameComponent: String {
        switch self {
        case .lastHour: "last-hour"
        case .last24Hours: "last-24-hours"
        case .last7Days: "last-7-days"
        }
    }
}

enum DiagnosticExportFileName {
    static func make(
        window: DiagnosticExportWindow,
        date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "md2png-diagnostics-\(formatter.string(from: date))-\(window.fileNameComponent).json"
    }
}
