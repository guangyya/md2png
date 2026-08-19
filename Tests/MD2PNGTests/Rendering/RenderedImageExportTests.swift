import AppKit
import XCTest
@testable import MD2PNG

final class RenderedImageExportTests: XCTestCase {
    func testCornerPreferenceDefaultsSafelyAndPersistsSelection() throws {
        let suiteName = "RenderCornerPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = RenderCornerPreference(defaults: defaults)

        XCTAssertEqual(preference.selectedStyle, .square)
        preference.select(.rounded)
        XCTAssertEqual(preference.selectedStyle, .rounded)

        defaults.set("unsupported", forKey: RenderCornerPreference.defaultsKey)
        XCTAssertEqual(preference.selectedStyle, .square)
    }

    func testRoundedCornerRadiusAdaptsToOutputWidthWithinSafeLimits() {
        XCTAssertEqual(
            RenderedImageStyler.roundedCornerRadius(
                for: NSSize(width: 720, height: 1_000)
            ),
            24
        )
        XCTAssertEqual(
            RenderedImageStyler.roundedCornerRadius(
                for: NSSize(width: 1_120, height: 1_000)
            ),
            33.6,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RenderedImageStyler.roundedCornerRadius(
                for: NSSize(width: 1_520, height: 1_000)
            ),
            45.6,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RenderedImageStyler.roundedCornerRadius(
                for: NSSize(width: 2_000, height: 40)
            ),
            20
        )
    }

    @MainActor
    func testSquareStyleReturnsTheOriginalImageWithoutReprocessing() throws {
        let image = try makeRetinaImage(
            pointSize: NSSize(width: 32, height: 24),
            pixelSize: NSSize(width: 64, height: 48)
        )

        XCTAssertTrue(try RenderedImageStyler.apply(.square, to: image) === image)
    }

    @MainActor
    func testRoundedStylePreservesDimensionsAndMakesOnlyCornersTransparent() throws {
        let image = try makeRetinaImage(
            pointSize: NSSize(width: 32, height: 24),
            pixelSize: NSSize(width: 64, height: 48),
            fillColor: .systemRed
        )

        let styled = try RenderedImageStyler.apply(.rounded, to: image)
        let exported = try XCTUnwrap(NSBitmapImageRep(
            data: RenderedImageExport.pngData(for: styled)
        ))
        let original = try XCTUnwrap(NSBitmapImageRep(
            data: RenderedImageExport.pngData(for: image)
        ))
        let tiff = try XCTUnwrap(styled.tiffRepresentation)
        let tiffBitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

        XCTAssertEqual(RenderedImageExport.pixelSize(of: styled), NSSize(width: 64, height: 48))
        XCTAssertEqual(styled.size, image.size)
        XCTAssertLessThan(try XCTUnwrap(exported.colorAt(x: 0, y: 0)).alphaComponent, 0.05)
        XCTAssertLessThan(try XCTUnwrap(tiffBitmap.colorAt(x: 0, y: 0)).alphaComponent, 0.05)
        XCTAssertGreaterThan(try XCTUnwrap(exported.colorAt(x: 32, y: 24)).alphaComponent, 0.95)
        XCTAssertGreaterThan(try XCTUnwrap(original.colorAt(x: 0, y: 0)).alphaComponent, 0.95)
    }

    @MainActor
    func testRoundedStyleDoesNotResampleInteriorPixels() throws {
        let image = try makePixelPatternImage(
            pointSize: NSSize(width: 64, height: 48),
            pixelSize: NSSize(width: 128, height: 96)
        )
        let original = try XCTUnwrap(NSBitmapImageRep(
            data: RenderedImageExport.pngData(for: image)
        ))

        let styled = try RenderedImageStyler.apply(.rounded, to: image)
        let exported = try XCTUnwrap(NSBitmapImageRep(
            data: RenderedImageExport.pngData(for: styled)
        ))

        for y in 24 ..< 72 {
            for x in 24 ..< 104 {
                var actual = [Int](repeating: 0, count: exported.samplesPerPixel)
                var expected = [Int](repeating: 0, count: original.samplesPerPixel)
                exported.getPixel(&actual, atX: x, y: y)
                original.getPixel(&expected, atX: x, y: y)
                XCTAssertEqual(
                    actual,
                    expected,
                    "Pixel changed at (\(x), \(y))"
                )
            }
        }
    }

    func testPNGExportPreservesTheHighestResolutionRepresentation() throws {
        let image = try makeRetinaImage(
            pointSize: NSSize(width: 120, height: 80),
            pixelSize: NSSize(width: 240, height: 160)
        )

        XCTAssertEqual(RenderedImageExport.pixelSize(of: image), NSSize(width: 240, height: 160))
        let data = try RenderedImageExport.pngData(for: image)
        let exported = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(exported.pixelsWide, 240)
        XCTAssertEqual(exported.pixelsHigh, 160)
    }

    func testPNGWriteCreatesAReadableFileAtomically() throws {
        let image = try makeRetinaImage(
            pointSize: NSSize(width: 64, height: 48),
            pixelSize: NSSize(width: 128, height: 96)
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RenderedImageExportTests-\(UUID().uuidString)", isDirectory: true)
        let output = directory.appendingPathComponent("render.png")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try RenderedImageExport.writePNG(image, to: output)

        let exported = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        XCTAssertEqual(exported.pixelsWide, 128)
        XCTAssertEqual(exported.pixelsHigh, 96)
    }

    func testPNGWriteMapsFilesystemFailureToSafeAppError() throws {
        let image = try makeRetinaImage(
            pointSize: NSSize(width: 20, height: 20),
            pixelSize: NSSize(width: 40, height: 40)
        )
        let missingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)", isDirectory: true)
        let output = missingDirectory.appendingPathComponent("render.png")

        XCTAssertThrowsError(try RenderedImageExport.writePNG(image, to: output)) { error in
            guard case AppError.pngWriteFailed = error else {
                return XCTFail("Expected pngWriteFailed, got \(error)")
            }
        }
    }

    func testPreviewTemporaryStoreUsesAnIsolatedDirectoryAndCleansUp() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PreviewTemporaryImageStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let firstStore = PreviewTemporaryImageStore(baseDirectory: baseDirectory)
        let secondStore = PreviewTemporaryImageStore(baseDirectory: baseDirectory)
        let image = try makeRetinaImage(
            pointSize: NSSize(width: 32, height: 24),
            pixelSize: NSSize(width: 64, height: 48)
        )

        let firstURL = try firstStore.replace(with: image)
        let secondURL = try secondStore.replace(with: image)

        XCTAssertNotEqual(firstStore.directoryURL, secondStore.directoryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        firstStore.clear()
        XCTAssertNil(firstStore.currentFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstStore.directoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testPreviewTemporaryStoreReplacesThePreviousPNG() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PreviewTemporaryImageStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let store = PreviewTemporaryImageStore(baseDirectory: baseDirectory)
        let first = try makeRetinaImage(
            pointSize: NSSize(width: 32, height: 24),
            pixelSize: NSSize(width: 64, height: 48)
        )
        let second = try makeRetinaImage(
            pointSize: NSSize(width: 80, height: 60),
            pixelSize: NSSize(width: 160, height: 120)
        )

        let firstURL = try store.replace(with: first)
        let secondURL = try store.replace(with: second)
        let exported = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: secondURL)))

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertEqual(exported.pixelsWide, 160)
        XCTAssertEqual(exported.pixelsHigh, 120)
        let generationDirectories = try FileManager.default.contentsOfDirectory(
            atPath: store.directoryURL.path
        )
        XCTAssertEqual(generationDirectories.count, 1)
        XCTAssertEqual(secondURL.lastPathComponent, "md2png-last-render.png")
        XCTAssertEqual(
            secondURL.deletingLastPathComponent().lastPathComponent,
            generationDirectories[0]
        )
    }

    func testPreviewTemporaryStoreUsesDistinctGenerationURLs() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PreviewTemporaryImageStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let store = PreviewTemporaryImageStore(baseDirectory: baseDirectory)
        let image = try makeRetinaImage(
            pointSize: NSSize(width: 32, height: 24),
            pixelSize: NSSize(width: 64, height: 48)
        )

        let firstURL = try store.replace(with: image)
        let secondURL = try store.replace(with: image)

        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertFalse(store.clear(ifCurrentFileURL: firstURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondURL.path))
        XCTAssertTrue(store.clear(ifCurrentFileURL: secondURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondURL.path))
    }

    func testPreviewTemporaryStoreCleansUpWhenReleased() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PreviewTemporaryImageStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        var store: PreviewTemporaryImageStore? = PreviewTemporaryImageStore(
            baseDirectory: baseDirectory
        )
        let directoryURL = try XCTUnwrap(store?.directoryURL)
        let image = try makeRetinaImage(
            pointSize: NSSize(width: 32, height: 24),
            pixelSize: NSSize(width: 64, height: 48)
        )
        _ = try store?.replace(with: image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.path))

        store = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
    }

    private func makeRetinaImage(
        pointSize: NSSize,
        pixelSize: NSSize,
        fillColor: NSColor? = nil
    ) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = pointSize
        if let fillColor {
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            fillColor.setFill()
            NSRect(origin: .zero, size: pixelSize).fill()
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = NSImage(size: pointSize)
        image.addRepresentation(bitmap)
        return image
    }

    private func makePixelPatternImage(
        pointSize: NSSize,
        pixelSize: NSSize
    ) throws -> NSImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [.alphaNonpremultiplied],
            bytesPerRow: Int(pixelSize.width) * 4,
            bitsPerPixel: 32
        ))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                let offset = y * bitmap.bytesPerRow + x * 4
                pixels[offset] = UInt8((x * 17 + y * 3) % 256)
                pixels[offset + 1] = UInt8((x * 5 + y * 19) % 256)
                pixels[offset + 2] = UInt8((x * 11 + y * 7) % 256)
                pixels[offset + 3] = 255
            }
        }
        bitmap.size = pointSize
        let image = NSImage(size: pointSize)
        image.addRepresentation(bitmap)
        return image
    }
}
