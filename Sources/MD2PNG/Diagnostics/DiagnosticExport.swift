import Foundation

enum DiagnosticExportWindow: String, Codable, CaseIterable, Sendable {
    case lastHour = "last_hour"
    case last24Hours = "last_24_hours"
    case last7Days = "last_7_days"

    var duration: TimeInterval {
        switch self {
        case .lastHour:
            return 60 * 60
        case .last24Hours:
            return 24 * 60 * 60
        case .last7Days:
            return 7 * 24 * 60 * 60
        }
    }
}

struct DiagnosticApplicationInfo: Codable, Equatable, Sendable {
    let name: String
    let version: String
    let build: String
    let sourceCommit: String?
    let configuration: String

    static func current(bundle: Bundle = .main) -> DiagnosticApplicationInfo {
        DiagnosticApplicationInfo(
            name: "md2png",
            version: safeBundleValue(
                bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            ),
            build: safeBundleValue(
                bundle.object(forInfoDictionaryKey: "CFBundleVersion")
            ),
            sourceCommit: AppMetadata.shortSourceCommit(from: bundle.object(
                forInfoDictionaryKey: AppMetadata.sourceCommitInfoDictionaryKey
            ) as? String),
            configuration: AppBuildConfiguration.current == .debug ? "debug" : "release"
        )
    }

    private static func safeBundleValue(_ value: Any?) -> String {
        guard let value = value as? String else { return "unknown" }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ._-")
        guard (1...64).contains(value.count),
              value.unicodeScalars.allSatisfy(allowed.contains) else {
            return "unknown"
        }
        return value
    }
}

struct DiagnosticSystemInfo: Codable, Equatable, Sendable {
    let macOSVersion: String
    let architecture: String

    static let current = DiagnosticSystemInfo(
        macOSVersion: AppRuntimeInfo.macOSVersion,
        architecture: AppRuntimeInfo.architecture
    )
}

struct DiagnosticExportInterval: Codable, Equatable, Sendable {
    let selection: DiagnosticExportWindow
    let start: Date
    let end: Date
}

struct DiagnosticExport: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schema: Int
    let generatedAt: Date
    let interval: DiagnosticExportInterval
    let application: DiagnosticApplicationInfo
    let system: DiagnosticSystemInfo
    let events: [DiagnosticEvent]

    init(
        generatedAt: Date,
        interval: DiagnosticExportInterval,
        application: DiagnosticApplicationInfo,
        system: DiagnosticSystemInfo,
        events: [DiagnosticEvent]
    ) {
        schema = Self.schemaVersion
        self.generatedAt = generatedAt
        self.interval = interval
        self.application = application
        self.system = system
        self.events = events
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func encodedString() throws -> String {
        guard let string = String(data: try encodedData(), encoding: .utf8) else {
            throw DiagnosticExportError.invalidEncoding
        }
        return string
    }
}

enum DiagnosticExportError: Error, Equatable {
    case storageUnavailable
    case invalidEncoding
}
