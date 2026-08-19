import AppKit
import XCTest
@testable import MD2PNG

final class PreviewDragSourceTests: XCTestCase {
    @MainActor
    func testExportWritesSuggestedPNGWithCapturedPixels() throws {
        let parent = try temporaryDirectory(named: "PreviewDragExportTests")
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = PreviewDragExportStore(parentDirectoryURL: parent)

        let export = try store.export(
            image: try makeImage(pixelsWide: 240, pixelsHigh: 160, color: .blue),
            generationID: UUID(),
            suggestedFilename: "Monthly Product Update.png"
        )

        XCTAssertEqual(export.fileURL.lastPathComponent, "Monthly Product Update.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.fileURL.path))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: export.fileURL)))
        XCTAssertEqual(bitmap.pixelsWide, 240)
        XCTAssertEqual(bitmap.pixelsHigh, 160)
    }

    @MainActor
    func testPasteboardPublishesFileURLAndPNGForCompatibility() throws {
        let parent = try temporaryDirectory(named: "PreviewDragPasteboardTests")
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = PreviewDragExportStore(parentDirectoryURL: parent)
        let export = try store.export(
            image: try makeImage(pixelsWide: 80, pixelsHigh: 60, color: .red),
            generationID: UUID(),
            suggestedFilename: "Compatibility.png"
        )

        let item = try PreviewDragItemFactory.makePasteboardItem(for: export)

        XCTAssertTrue(item.types.contains(.fileURL))
        XCTAssertTrue(item.types.contains(.png))
        XCTAssertEqual(item.string(forType: .fileURL), export.fileURL.absoluteString)
        XCTAssertEqual(item.data(forType: .png), export.pngData)
    }

    @MainActor
    func testSamePreviewGenerationReusesOneFileAndReplacementIsIndependent() throws {
        let parent = try temporaryDirectory(named: "PreviewDragGenerationTests")
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = PreviewDragExportStore(parentDirectoryURL: parent)
        let firstGeneration = UUID()
        let secondGeneration = UUID()

        let first = try store.export(
            image: try makeImage(pixelsWide: 80, pixelsHigh: 60, color: .red),
            generationID: firstGeneration,
            suggestedFilename: "First.png"
        )
        let repeated = try store.export(
            image: try makeImage(pixelsWide: 20, pixelsHigh: 10, color: .black),
            generationID: firstGeneration,
            suggestedFilename: "Ignored replacement.png"
        )
        let second = try store.export(
            image: try makeImage(pixelsWide: 320, pixelsHigh: 200, color: .green),
            generationID: secondGeneration,
            suggestedFilename: "Second.png"
        )

        XCTAssertEqual(repeated.id, first.id)
        XCTAssertEqual(repeated.fileURL, first.fileURL)
        XCTAssertNotEqual(second.id, first.id)
        let firstBitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: first.fileURL)))
        let secondBitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: second.fileURL)))
        XCTAssertEqual([firstBitmap.pixelsWide, firstBitmap.pixelsHigh], [80, 60])
        XCTAssertEqual([secondBitmap.pixelsWide, secondBitmap.pixelsHigh], [320, 200])
    }

    @MainActor
    func testCancelledUnusedExportIsRemovedButAcceptedExportSurvives() throws {
        let parent = try temporaryDirectory(named: "PreviewDragLifetimeTests")
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = PreviewDragExportStore(parentDirectoryURL: parent)

        let cancelled = try store.export(
            image: try makeImage(pixelsWide: 40, pixelsHigh: 30, color: .orange),
            generationID: UUID(),
            suggestedFilename: "Cancelled.png"
        )
        store.finishExport(cancelled.id, operation: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.fileURL.path))

        let acceptedGeneration = UUID()
        let accepted = try store.export(
            image: try makeImage(pixelsWide: 50, pixelsHigh: 35, color: .purple),
            generationID: acceptedGeneration,
            suggestedFilename: "Accepted.png"
        )
        store.finishExport(accepted.id, operation: .copy)
        store.finishExport(accepted.id, operation: [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: accepted.fileURL.path))

        store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: accepted.fileURL.path))
    }

    @MainActor
    func testStaleDragCompletionCannotRemoveRegeneratedExport() throws {
        let parent = try temporaryDirectory(named: "PreviewDragStaleCompletionTests")
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = PreviewDragExportStore(parentDirectoryURL: parent)
        let generationID = UUID()
        let original = try store.export(
            image: try makeImage(pixelsWide: 40, pixelsHigh: 30, color: .red),
            generationID: generationID,
            suggestedFilename: "Original.png"
        )
        try FileManager.default.removeItem(at: original.fileURL)
        let regenerated = try store.export(
            image: try makeImage(pixelsWide: 50, pixelsHigh: 35, color: .blue),
            generationID: generationID,
            suggestedFilename: "Regenerated.png"
        )

        store.finishExport(original.id, operation: [])

        XCTAssertNotEqual(regenerated.id, original.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: regenerated.fileURL.path))
    }

    @MainActor
    func testStoreDeinitRemovesAcceptedTemporaryFile() throws {
        let parent = try temporaryDirectory(named: "PreviewDragDeinitTests")
        defer { try? FileManager.default.removeItem(at: parent) }
        var fileURL: URL?

        do {
            let store = PreviewDragExportStore(parentDirectoryURL: parent)
            let export = try store.export(
                image: try makeImage(pixelsWide: 32, pixelsHigh: 24, color: .cyan),
                generationID: UUID(),
                suggestedFilename: "Session.png"
            )
            store.finishExport(export.id, operation: .copy)
            fileURL = export.fileURL
            XCTAssertTrue(FileManager.default.fileExists(atPath: export.fileURL.path))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(fileURL).path))
    }

    @MainActor
    func testInvalidParentReportsWriteFailureAndSanitizesFilename() throws {
        XCTAssertEqual(
            PreviewDragItemFactory.safeFilename(from: "../../Dragged report"),
            "Dragged report.png"
        )
        let invalidParent = try temporaryDirectory(named: "PreviewDragFailureTests")
            .appendingPathComponent("regular-file")
        try Data("not a directory".utf8).write(to: invalidParent)
        defer { try? FileManager.default.removeItem(at: invalidParent.deletingLastPathComponent()) }
        let store = PreviewDragExportStore(parentDirectoryURL: invalidParent)

        XCTAssertThrowsError(try store.export(
            image: try makeImage(pixelsWide: 40, pixelsHigh: 30, color: .orange),
            generationID: UUID(),
            suggestedFilename: "Dragged report"
        )) { error in
            guard let appError = error as? AppError,
                  case .pngWriteFailed = appError else {
                return XCTFail("Expected pngWriteFailed, got \(error)")
            }
        }
    }

    func testDraggingThumbnailIsBoundedCenteredAndPreservesAspectRatio() {
        let frame = PreviewDragItemFactory.draggingFrame(
            imageSize: NSSize(width: 1_200, height: 800),
            centeredAt: NSPoint(x: 300, y: 200)
        )

        XCTAssertEqual(frame.width, 180, accuracy: 0.001)
        XCTAssertEqual(frame.height, 120, accuracy: 0.001)
        XCTAssertEqual(frame.midX, 300, accuracy: 0.001)
        XCTAssertEqual(frame.midY, 200, accuracy: 0.001)
        XCTAssertEqual(frame.width / frame.height, 1.5, accuracy: 0.001)
    }

    @MainActor
    func testPreviewControllerExportsCurrentImageWithoutChangingTheClipboard() throws {
        _ = NSApplication.shared
        var copyCount = 0
        let controller = PreviewController(copyImage: { _ in
            copyCount += 1
            return copyCount
        })
        defer { controller.close() }
        controller.show(
            image: try makeImage(pixelsWide: 120, pixelsHigh: 90, color: .purple),
            markdown: "# Drag Export"
        )

        let export = try XCTUnwrap(controller.dragExportForTesting())

        XCTAssertEqual(export.fileURL.lastPathComponent, "Drag Export.png")
        XCTAssertEqual(copyCount, 0)
    }

    private func temporaryDirectory(named prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private func makeImage(
        pixelsWide: Int,
        pixelsHigh: Int,
        color: NSColor
    ) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        color.setFill()
        NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pixelsWide, height: pixelsHigh))
        image.addRepresentation(bitmap)
        return image
    }
}
