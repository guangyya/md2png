import Foundation

enum DiagnosticCategory: String, Codable, CaseIterable, Sendable {
    case appLifecycle = "app_lifecycle"
    case renderer
    case webKitRecovery = "webkit_recovery"
    case clipboard
    case shortcut
    case resource
    case releases
    case selfTest = "self_test"
}

enum DiagnosticStage: String, Codable, CaseIterable, Sendable {
    case applicationLaunch = "application_launch"
    case applicationActive = "application_active"
    case applicationTermination = "application_termination"
    case shortcutRegistration = "shortcut_registration"
    case rendererPageLookup = "renderer_page_lookup"
    case exampleResourceLookup = "example_resource_lookup"
    case selfTestMarkdownLookup = "self_test_markdown_lookup"
    case rendererLoad = "renderer_load"
    case renderRequest = "render_request"
    case rendererExecution = "renderer_execution"
    case renderJavaScript = "render_javascript"
    case renderSnapshot = "render_snapshot"
    case renderCompletion = "render_completion"
    case contentProcessTermination = "content_process_termination"
    case rendererRecovery = "renderer_recovery"
    case watchdogTimeout = "watchdog_timeout"
    case clipboardRead = "clipboard_read"
    case clipboardWrite = "clipboard_write"
    case clipboardOwnership = "clipboard_ownership"
    case releasesOpen = "releases_open"
    case fullReleaseNotesOpen = "full_release_notes_open"
    case selfTestRun = "self_test_run"
}

enum DiagnosticResult: String, Codable, Sendable {
    case started
    case queued
    case succeeded
    case failed
    case cancelled
    case ignored
    case available
    case unavailable
    case owned
    case external
    case accepted
    case deferred
}

enum DiagnosticLevel: String, Codable, Sendable {
    case info
    case error
    case verbose
}

enum DiagnosticClipboardType: String, Codable, Sendable {
    case markdown
    case png
    case empty
    case unknown
}

enum DiagnosticClipboardOwnership: String, Codable, Sendable {
    case owned
    case external
    case unknown
}

struct DiagnosticOperationID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    let rawValue: String

    init() {
        rawValue = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(12)
            .lowercased()
    }

    init?(rawValue: String) {
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        guard rawValue.count == 12,
              rawValue.unicodeScalars.allSatisfy(allowed.contains) else {
            return nil
        }
        self.rawValue = rawValue
    }
}

struct DiagnosticErrorMetadata: Codable, Equatable, Sendable {
    let domain: String
    let code: Int

    init(_ error: any Error) {
        let nsError = error as NSError
        domain = Self.safeDomain(for: error, nsError: nsError)
        code = nsError.code
    }

    private static func safeDomain(
        for error: any Error,
        nsError: NSError
    ) -> String {
        switch error {
        case is AppError:
            return "md2png.app"
        case is RendererFailure:
            return RendererFailure.errorDomain
        case is UpdateError:
            return "md2png.update"
        case is PackagedRenderSelfTestFailure:
            return "md2png.self_test"
        default:
            let allowedSystemDomains = Set([
                NSCocoaErrorDomain,
                NSPOSIXErrorDomain,
                NSOSStatusErrorDomain,
                NSURLErrorDomain,
                "NSMachErrorDomain",
                "WKErrorDomain"
            ])
            return allowedSystemDomains.contains(nsError.domain)
                ? nsError.domain
                : "redacted"
        }
    }
}

struct DiagnosticDimensions: Codable, Equatable, Sendable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

struct DiagnosticEvent: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schema: Int
    let timestamp: Date
    let category: DiagnosticCategory
    let stage: DiagnosticStage
    let result: DiagnosticResult
    let level: DiagnosticLevel
    let operationID: DiagnosticOperationID?
    let durationMilliseconds: Int?
    let error: DiagnosticErrorMetadata?
    let clipboardType: DiagnosticClipboardType?
    let clipboardOwnership: DiagnosticClipboardOwnership?
    let dimensions: DiagnosticDimensions?
    let itemCount: Int?
    let failureCount: Int?

    init(
        timestamp: Date,
        category: DiagnosticCategory,
        stage: DiagnosticStage,
        result: DiagnosticResult,
        level: DiagnosticLevel = .info,
        operationID: DiagnosticOperationID? = nil,
        durationMilliseconds: Int? = nil,
        error: DiagnosticErrorMetadata? = nil,
        clipboardType: DiagnosticClipboardType? = nil,
        clipboardOwnership: DiagnosticClipboardOwnership? = nil,
        dimensions: DiagnosticDimensions? = nil,
        itemCount: Int? = nil,
        failureCount: Int? = nil
    ) {
        schema = Self.schemaVersion
        self.timestamp = timestamp
        self.category = category
        self.stage = stage
        self.result = result
        self.level = level
        self.operationID = operationID
        self.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
        self.error = error
        self.clipboardType = clipboardType
        self.clipboardOwnership = clipboardOwnership
        self.dimensions = dimensions
        self.itemCount = itemCount.map { max(0, $0) }
        self.failureCount = failureCount.map { max(0, $0) }
    }
}

enum DiagnosticDuration {
    static func milliseconds(since start: UInt64) -> Int {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        return Int(min(elapsed / 1_000_000, UInt64(Int.max)))
    }
}
