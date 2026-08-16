import AppKit

enum RenderedImageExport {
    static func pixelSize(of image: NSImage) -> NSSize {
        let bitmapRepresentations = image.representations.compactMap { $0 as? NSBitmapImageRep }
        guard let representation = bitmapRepresentations.max(by: {
            $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
        }) else {
            return image.size
        }
        return NSSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }

    static func pngData(for image: NSImage) throws -> Data {
        if let representation = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }),
           let png = representation.representation(using: .png, properties: [:]) {
            return png
        }
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:]) else {
            throw AppError.pngEncodingFailed
        }
        return png
    }

    static func writePNG(_ image: NSImage, to url: URL) throws {
        do {
            try pngData(for: image).write(to: url, options: .atomic)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.pngWriteFailed
        }
    }
}

final class PreviewTemporaryImageStore {
    let directoryURL: URL
    private(set) var currentFileURL: URL?
    private let fileManager: FileManager

    init(
        baseDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default,
        identifier: UUID = UUID()
    ) {
        self.fileManager = fileManager
        directoryURL = baseDirectory.appendingPathComponent(
            "md2png-preview-\(identifier.uuidString)",
            isDirectory: true
        )
    }

    deinit {
        clear()
    }

    func replace(with image: NSImage) throws -> URL {
        clear()
        do {
            let generationDirectory = directoryURL.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: generationDirectory,
                withIntermediateDirectories: true
            )
            let fileURL = generationDirectory.appendingPathComponent("md2png-last-render.png")
            try RenderedImageExport.writePNG(image, to: fileURL)
            currentFileURL = fileURL
            return fileURL
        } catch {
            clear()
            throw error
        }
    }

    @discardableResult
    func clear(ifCurrentFileURL fileURL: URL) -> Bool {
        guard currentFileURL == fileURL else { return false }
        clear()
        return true
    }

    func clear() {
        try? fileManager.removeItem(at: directoryURL)
        currentFileURL = nil
    }
}
