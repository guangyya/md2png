import Foundation

struct DiagnosticRetentionPolicy: Equatable, Sendable {
    static let standard = DiagnosticRetentionPolicy(
        maximumAge: 7 * 24 * 60 * 60,
        maximumFileSize: 1_000_000,
        maximumFileCount: 5
    )

    let maximumAge: TimeInterval
    let maximumFileSize: Int
    let maximumFileCount: Int

    init(
        maximumAge: TimeInterval,
        maximumFileSize: Int,
        maximumFileCount: Int
    ) {
        self.maximumAge = max(0, maximumAge)
        self.maximumFileSize = max(1, maximumFileSize)
        self.maximumFileCount = max(1, maximumFileCount)
    }
}

struct DiagnosticLoggerConfiguration: Sendable {
    let directoryURL: URL
    let retentionPolicy: DiagnosticRetentionPolicy
    let includesVerboseEvents: Bool
    let isEnabled: Bool
    let now: @Sendable () -> Date
    let applicationInfo: DiagnosticApplicationInfo
    let systemInfo: DiagnosticSystemInfo

    static func live(
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) -> DiagnosticLoggerConfiguration {
        let libraryURL = fileManager.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
#if DEBUG
        let includesVerboseEvents = true
#else
        let includesVerboseEvents = false
#endif
        return DiagnosticLoggerConfiguration(
            directoryURL: libraryURL
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("md2png", isDirectory: true)
                .appendingPathComponent("Diagnostics", isDirectory: true),
            retentionPolicy: .standard,
            includesVerboseEvents: includesVerboseEvents,
            isEnabled: true,
            now: Date.init,
            applicationInfo: .current(bundle: bundle),
            systemInfo: .current
        )
    }

    static let disabled = DiagnosticLoggerConfiguration(
        directoryURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("md2png-disabled-diagnostics", isDirectory: true),
        retentionPolicy: .standard,
        includesVerboseEvents: false,
        isEnabled: false,
        now: Date.init,
        applicationInfo: DiagnosticApplicationInfo(
            name: "md2png",
            version: "unknown",
            build: "unknown",
            sourceCommit: nil,
            configuration: "debug"
        ),
        systemInfo: .current
    )
}

final class DiagnosticLogger: @unchecked Sendable {
    static let shared = DiagnosticLogger(configuration: .live())
    static let disabled = DiagnosticLogger(configuration: .disabled)

    let storageDirectoryURL: URL

    private let configuration: DiagnosticLoggerConfiguration
    private let queue = DispatchQueue(
        label: "io.github.guangyya.md2png.diagnostics",
        qos: .utility
    )
    private let store: DiagnosticLogStore

    init(
        configuration: DiagnosticLoggerConfiguration,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        storageDirectoryURL = configuration.directoryURL
        store = DiagnosticLogStore(
            directoryURL: configuration.directoryURL,
            retentionPolicy: configuration.retentionPolicy,
            now: configuration.now,
            fileManager: fileManager
        )
    }

    func record(
        category: DiagnosticCategory,
        stage: DiagnosticStage,
        result: DiagnosticResult,
        level: DiagnosticLevel = .info,
        operationID: DiagnosticOperationID? = nil,
        durationMilliseconds: Int? = nil,
        error: (any Error)? = nil,
        clipboardType: DiagnosticClipboardType? = nil,
        clipboardOwnership: DiagnosticClipboardOwnership? = nil,
        dimensions: DiagnosticDimensions? = nil,
        itemCount: Int? = nil,
        failureCount: Int? = nil
    ) {
        guard configuration.isEnabled,
              level != .verbose || configuration.includesVerboseEvents else {
            return
        }
        let event = DiagnosticEvent(
            timestamp: configuration.now(),
            category: category,
            stage: stage,
            result: result,
            level: level,
            operationID: operationID,
            durationMilliseconds: durationMilliseconds,
            error: error.map(DiagnosticErrorMetadata.init),
            clipboardType: clipboardType,
            clipboardOwnership: clipboardOwnership,
            dimensions: dimensions,
            itemCount: itemCount,
            failureCount: failureCount
        )
        queue.async { [store] in
            try? store.append(event)
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume()
            }
        }
    }

    func export(
        window: DiagnosticExportWindow,
        now: Date? = nil
    ) async throws -> DiagnosticExport {
        let exportDate = now ?? configuration.now()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [configuration, store] in
                do {
                    let start = exportDate.addingTimeInterval(-window.duration)
                    let events = try store.events(from: start, through: exportDate)
                    continuation.resume(returning: DiagnosticExport(
                        generatedAt: exportDate,
                        interval: DiagnosticExportInterval(
                            selection: window,
                            start: start,
                            end: exportDate
                        ),
                        application: configuration.applicationInfo,
                        system: configuration.systemInfo,
                        events: events
                    ))
                } catch {
                    continuation.resume(throwing: DiagnosticExportError.storageUnavailable)
                }
            }
        }
    }

    func deleteAllLogs() async {
        await withCheckedContinuation { continuation in
            queue.async { [store] in
                try? store.deleteAll()
                continuation.resume()
            }
        }
    }
}

private final class DiagnosticLogStore: @unchecked Sendable {
    private let directoryURL: URL
    private let retentionPolicy: DiagnosticRetentionPolicy
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var currentFileURL: URL?

    init(
        directoryURL: URL,
        retentionPolicy: DiagnosticRetentionPolicy,
        now: @escaping @Sendable () -> Date,
        fileManager: FileManager
    ) {
        self.directoryURL = directoryURL
        self.retentionPolicy = retentionPolicy
        self.now = now
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func append(_ event: DiagnosticEvent) throws {
        try prepareDirectory()
        try pruneExpiredFiles()
        var data = try encoder.encode(event)
        data.append(0x0A)
        guard data.count <= retentionPolicy.maximumFileSize else { return }

        let fileURL = try writableFile(forAdditionalBytes: data.count)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try? fileManager.setAttributes(
            [.modificationDate: event.timestamp],
            ofItemAtPath: fileURL.path
        )
        try enforceFileCount(keeping: fileURL)
    }

    func events(from start: Date, through end: Date) throws -> [DiagnosticEvent] {
        if !fileManager.fileExists(atPath: directoryURL.path) {
            return []
        }
        try pruneExpiredFiles()
        var events: [DiagnosticEvent] = []
        for url in try logFileURLs() {
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            for line in data.split(separator: 0x0A) {
                guard let event = try? decoder.decode(DiagnosticEvent.self, from: Data(line)),
                      event.schema == DiagnosticEvent.schemaVersion,
                      event.timestamp >= start,
                      event.timestamp <= end else {
                    continue
                }
                events.append(event)
            }
        }
        return events.sorted {
            if $0.timestamp == $1.timestamp {
                return ($0.operationID?.rawValue ?? "") < ($1.operationID?.rawValue ?? "")
            }
            return $0.timestamp < $1.timestamp
        }
    }

    func deleteAll() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        for url in try logFileURLs() {
            try? fileManager.removeItem(at: url)
        }
        currentFileURL = nil
    }

    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func writableFile(forAdditionalBytes byteCount: Int) throws -> URL {
        if let currentFileURL,
           fileManager.fileExists(atPath: currentFileURL.path),
           try fileSize(at: currentFileURL) + byteCount <= retentionPolicy.maximumFileSize {
            return currentFileURL
        }

        if let newest = try logFileURLs().last,
           try fileSize(at: newest) + byteCount <= retentionPolicy.maximumFileSize {
            currentFileURL = newest
            return newest
        }

        let fileURL = nextFileURL()
        guard fileManager.createFile(atPath: fileURL.path, contents: nil) else {
            throw DiagnosticExportError.storageUnavailable
        }
        currentFileURL = fileURL
        return fileURL
    }

    private func nextFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let timestamp = formatter.string(from: now())
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return directoryURL.appendingPathComponent(
            "diagnostics-\(timestamp)-\(suffix).jsonl"
        )
    }

    private func pruneExpiredFiles() throws {
        let cutoff = now().addingTimeInterval(-retentionPolicy.maximumAge)
        for url in try logFileURLs() {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modificationDate = values?.contentModificationDate,
               modificationDate < cutoff {
                try? fileManager.removeItem(at: url)
                if currentFileURL == url { currentFileURL = nil }
            }
        }
    }

    private func enforceFileCount(keeping currentURL: URL) throws {
        var urls = try logFileURLs()
        while urls.count > retentionPolicy.maximumFileCount {
            let removableIndex = urls.firstIndex { $0 != currentURL } ?? 0
            let removed = urls.remove(at: removableIndex)
            try? fileManager.removeItem(at: removed)
            if currentFileURL == removed { currentFileURL = nil }
        }
    }

    private func logFileURLs() throws -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        .filter {
            $0.lastPathComponent.hasPrefix("diagnostics-")
                && $0.pathExtension == "jsonl"
        }
        .sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.lastPathComponent < rhs.lastPathComponent
            }
            return lhsDate < rhsDate
        }
    }

    private func fileSize(at url: URL) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}
