import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import MD2PNG

final class PreviewDragSourceTests: XCTestCase {
    @MainActor
    func testFilePromiseUsesSuggestedNameAndWritesTheCapturedPNG() throws {
        let image = try makeImage(pixelsWide: 240, pixelsHigh: 160, color: .systemBlue)
        let provider = try PreviewDragItemFactory.makeFilePromiseProvider(
            image: image,
            suggestedFilename: "Monthly Product Update.png",
            onWriteError: {}
        )
        let promise = try XCTUnwrap(provider.userInfo as? PreviewPromisedPNG)
        let directory = temporaryDirectory(named: "PreviewDragPromiseTests")
        let output = directory.appendingPathComponent(promise.filename)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        XCTAssertEqual(provider.fileType, UTType.png.identifier)
        XCTAssertTrue(provider.delegate === promise)
        XCTAssertEqual(
            promise.filePromiseProvider(provider, fileNameForType: provider.fileType),
            "Monthly Product Update.png"
        )

        var writeError: Error?
        promise.filePromiseProvider(provider, writePromiseTo: output) { writeError = $0 }

        XCTAssertNil(writeError)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        XCTAssertEqual(bitmap.pixelsWide, 240)
        XCTAssertEqual(bitmap.pixelsHigh, 160)
    }

    @MainActor
    func testPromisesRemainGenerationSpecificAcrossReplacementRenders() throws {
        let firstProvider = try PreviewDragItemFactory.makeFilePromiseProvider(
            image: try makeImage(pixelsWide: 80, pixelsHigh: 60, color: .systemRed),
            suggestedFilename: "First.png",
            onWriteError: {}
        )
        let secondProvider = try PreviewDragItemFactory.makeFilePromiseProvider(
            image: try makeImage(pixelsWide: 320, pixelsHigh: 200, color: .systemGreen),
            suggestedFilename: "Second.png",
            onWriteError: {}
        )
        let firstPromise = try XCTUnwrap(firstProvider.userInfo as? PreviewPromisedPNG)
        let secondPromise = try XCTUnwrap(secondProvider.userInfo as? PreviewPromisedPNG)
        let directory = temporaryDirectory(named: "PreviewDragGenerationTests")
        let firstURL = directory.appendingPathComponent(firstPromise.filename)
        let secondURL = directory.appendingPathComponent(secondPromise.filename)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        firstPromise.filePromiseProvider(firstProvider, writePromiseTo: firstURL) { error in
            XCTAssertNil(error)
        }
        secondPromise.filePromiseProvider(secondProvider, writePromiseTo: secondURL) { error in
            XCTAssertNil(error)
        }

        let first = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: firstURL)))
        let second = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: secondURL)))
        XCTAssertEqual([first.pixelsWide, first.pixelsHigh], [80, 60])
        XCTAssertEqual([second.pixelsWide, second.pixelsHigh], [320, 200])
    }

    @MainActor
    func testPromiseSanitizesFilenameAndReportsDestinationWriteFailure() async throws {
        let image = try makeImage(pixelsWide: 40, pixelsHigh: 30, color: .systemOrange)
        let errorReported = expectation(description: "write failure reported")
        let provider = try PreviewDragItemFactory.makeFilePromiseProvider(
            image: image,
            suggestedFilename: "../../Dragged report",
            onWriteError: { errorReported.fulfill() }
        )
        let promise = try XCTUnwrap(provider.userInfo as? PreviewPromisedPNG)
        let missingParent = temporaryDirectory(named: "PreviewDragFailureTests")
            .appendingPathComponent("missing", isDirectory: true)
        let output = missingParent.appendingPathComponent("report.png")
        var writeError: Error?

        promise.filePromiseProvider(provider, writePromiseTo: output) { writeError = $0 }
        await fulfillment(of: [errorReported], timeout: 1)

        XCTAssertEqual(promise.filename, "Dragged report.png")
        guard let appError = writeError as? AppError,
              case .pngWriteFailed = appError else {
            return XCTFail("Expected pngWriteFailed, got \(String(describing: writeError))")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
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
    func testPreviewControllerPromisesCurrentImageWithoutChangingTheClipboard() throws {
        _ = NSApplication.shared
        var copyCount = 0
        let controller = PreviewController(copyImage: { _ in
            copyCount += 1
            return copyCount
        })
        defer { controller.close() }
        controller.show(
            image: try makeImage(pixelsWide: 120, pixelsHigh: 90, color: .systemPurple),
            markdown: "# Drag Export"
        )

        let provider = try XCTUnwrap(controller.dragFilePromiseProviderForTesting())
        let promise = try XCTUnwrap(provider.userInfo as? PreviewPromisedPNG)

        XCTAssertEqual(promise.filename, "Drag Export.png")
        XCTAssertEqual(copyCount, 0)
    }

    private func temporaryDirectory(named prefix: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

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
