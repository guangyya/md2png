import Foundation
import XCTest
@testable import MD2PNG

final class DiagnosticLoggerTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_787_000_000)

    func testStoredAndExportedEventsExcludeCraftedSensitiveErrorContent() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let logger = makeLogger(directoryURL: directoryURL)
        let canary = "PRIVATE_MARKDOWN_CANARY"
        let path = "/Users/private/Documents/secret.md"
        let url = "https://example.invalid/releases?token=secret"
        let error = NSError(
            domain: canary,
            code: 42,
            userInfo: [
                NSLocalizedDescriptionKey: "\(canary) \(path) \(url)"
            ]
        )

        logger.record(
            category: .renderer,
            stage: .renderCompletion,
            result: .failed,
            level: .error,
            error: error
        )
        await logger.flush()

        let stored = try diagnosticFiles(in: directoryURL)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined()
        let export = try await logger.export(window: .last24Hours, now: fixedNow)
        let encoded = try export.encodedString()
        XCTAssertEqual(export.events.count, 1)
        XCTAssertEqual(export.events.first?.error?.domain, "redacted")
        XCTAssertEqual(export.events.first?.error?.code, 42)
        for output in [stored, encoded] {
            XCTAssertFalse(output.contains(canary))
            XCTAssertFalse(output.contains(path))
            XCTAssertFalse(output.contains(url))
            XCTAssertFalse(output.contains("token=secret"))
        }
    }

    func testConcurrentEventsAreSerializedWithoutLoss() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let logger = makeLogger(directoryURL: directoryURL)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    logger.record(
                        category: .renderer,
                        stage: .renderRequest,
                        result: .queued
                    )
                }
            }
        }
        await logger.flush()

        let export = try await logger.export(window: .lastHour, now: fixedNow)
        XCTAssertEqual(export.events.count, 100)
    }

    func testRotationCapsFileSizeAndCount() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let logger = makeLogger(
            directoryURL: directoryURL,
            retentionPolicy: DiagnosticRetentionPolicy(
                maximumAge: 60 * 60,
                maximumFileSize: 420,
                maximumFileCount: 2
            )
        )

        for _ in 0..<20 {
            logger.record(
                category: .renderer,
                stage: .renderCompletion,
                result: .succeeded,
                operationID: DiagnosticOperationID(),
                dimensions: DiagnosticDimensions(width: 1_200, height: 800)
            )
        }
        await logger.flush()

        let files = try diagnosticFiles(in: directoryURL)
        XCTAssertEqual(files.count, 2)
        for file in files {
            let size = try XCTUnwrap(
                file.resourceValues(forKeys: [.fileSizeKey]).fileSize
            )
            XCTAssertLessThanOrEqual(size, 420)
        }
        let export = try await logger.export(window: .lastHour, now: fixedNow)
        XCTAssertLessThan(export.events.count, 20)
    }

    func testExpiredFilesAreDeletedBeforeAppending() async throws {
        let directoryURL = temporaryDirectoryURL()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let oldFile = directoryURL.appendingPathComponent("diagnostics-old.jsonl")
        try Data("malformed\n".utf8).write(to: oldFile)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedNow.addingTimeInterval(-8 * 24 * 60 * 60)],
            ofItemAtPath: oldFile.path
        )
        let logger = makeLogger(directoryURL: directoryURL)

        logger.record(
            category: .appLifecycle,
            stage: .applicationLaunch,
            result: .succeeded
        )
        await logger.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
        XCTAssertEqual(try diagnosticFiles(in: directoryURL).count, 1)
    }

    func testRestartReadsPriorEventsAndIgnoresMalformedLines() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let firstLogger = makeLogger(directoryURL: directoryURL)
        firstLogger.record(
            category: .appLifecycle,
            stage: .applicationLaunch,
            result: .succeeded
        )
        await firstLogger.flush()

        let malformedFile = directoryURL.appendingPathComponent(
            "diagnostics-malformed.jsonl"
        )
        try Data("not-json\n{}\n".utf8).write(to: malformedFile)
        let restartedLogger = makeLogger(directoryURL: directoryURL)
        let export = try await restartedLogger.export(
            window: .last7Days,
            now: fixedNow
        )

        XCTAssertEqual(export.events.count, 1)
        XCTAssertEqual(export.events.first?.stage, .applicationLaunch)
    }

    func testExportIncludesOnlyTheSelectedTimeWindowAndSafeRuntimeMetadata() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let oldLogger = makeLogger(
            directoryURL: directoryURL,
            now: fixedNow.addingTimeInterval(-2 * 60 * 60)
        )
        oldLogger.record(
            category: .appLifecycle,
            stage: .applicationLaunch,
            result: .succeeded
        )
        await oldLogger.flush()

        let recentLogger = makeLogger(directoryURL: directoryURL)
        recentLogger.record(
            category: .appLifecycle,
            stage: .applicationActive,
            result: .succeeded
        )
        await recentLogger.flush()

        let export = try await recentLogger.export(
            window: .lastHour,
            now: fixedNow
        )
        XCTAssertEqual(export.interval.selection, .lastHour)
        XCTAssertEqual(export.interval.start, fixedNow.addingTimeInterval(-60 * 60))
        XCTAssertEqual(export.interval.end, fixedNow)
        XCTAssertEqual(export.events.map(\.stage), [.applicationActive])
        XCTAssertEqual(export.application.version, "0.9.0")
        XCTAssertEqual(export.application.build, "9")
        XCTAssertEqual(export.system.architecture, "arm64")
    }

    func testWriteFailureIsSilentAndExplicitExportReportsUnavailableStorage() async {
        let directoryURL = temporaryDirectoryURL()
        try? Data("not-a-directory".utf8).write(to: directoryURL)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let logger = makeLogger(directoryURL: directoryURL)

        logger.record(
            category: .renderer,
            stage: .renderCompletion,
            result: .failed
        )
        await logger.flush()

        do {
            _ = try await logger.export(window: .lastHour, now: fixedNow)
            XCTFail("Expected an unavailable storage error")
        } catch {
            XCTAssertEqual(error as? DiagnosticExportError, .storageUnavailable)
        }
    }

    func testVerboseEventsCanBeDisabledWithoutChangingSchema() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let logger = makeLogger(
            directoryURL: directoryURL,
            includesVerboseEvents: false
        )

        logger.record(
            category: .renderer,
            stage: .renderJavaScript,
            result: .succeeded,
            level: .verbose
        )
        logger.record(
            category: .renderer,
            stage: .renderCompletion,
            result: .succeeded
        )
        await logger.flush()

        let export = try await logger.export(window: .lastHour, now: fixedNow)
        XCTAssertEqual(export.events.count, 1)
        XCTAssertEqual(export.events.first?.schema, DiagnosticEvent.schemaVersion)
    }

    func testDeleteAllLogsRequiresAnExplicitCall() async throws {
        let directoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let logger = makeLogger(directoryURL: directoryURL)
        logger.record(
            category: .appLifecycle,
            stage: .applicationLaunch,
            result: .succeeded
        )
        await logger.flush()
        XCTAssertFalse(try diagnosticFiles(in: directoryURL).isEmpty)

        await logger.deleteAllLogs()

        XCTAssertTrue(try diagnosticFiles(in: directoryURL).isEmpty)
    }

    func testOperationIDsAreShortRandomAndStrictlyValidated() {
        let first = DiagnosticOperationID()
        let second = DiagnosticOperationID()
        XCTAssertEqual(first.rawValue.count, 12)
        XCTAssertNotEqual(first, second)
        XCTAssertNotNil(DiagnosticOperationID(rawValue: "012345abcdef"))
        XCTAssertNil(DiagnosticOperationID(rawValue: "private-value"))
    }

    private func makeLogger(
        directoryURL: URL,
        retentionPolicy: DiagnosticRetentionPolicy = .standard,
        includesVerboseEvents: Bool = true,
        now: Date? = nil
    ) -> DiagnosticLogger {
        let currentDate = now ?? fixedNow
        return DiagnosticLogger(configuration: DiagnosticLoggerConfiguration(
            directoryURL: directoryURL,
            retentionPolicy: retentionPolicy,
            includesVerboseEvents: includesVerboseEvents,
            isEnabled: true,
            now: { currentDate },
            applicationInfo: DiagnosticApplicationInfo(
                name: "md2png",
                version: "0.9.0",
                build: "9",
                sourceCommit: "abcdef0",
                configuration: "debug"
            ),
            systemInfo: DiagnosticSystemInfo(
                macOSVersion: "26.0.0",
                architecture: "arm64"
            )
        ))
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "md2png-diagnostic-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private func diagnosticFiles(in directoryURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }
    }
}
