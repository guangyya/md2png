import AppKit
import UniformTypeIdentifiers

@MainActor
final class PreviewDragImageView: NSImageView, NSDraggingSource {
    typealias DraggingItemProvider = (NSEvent) throws -> NSDraggingItem?

    var draggingItemProvider: DraggingItemProvider?
    var draggingErrorHandler: ((Error) -> Void)?
    private var dragIsActive = false

    override func mouseDown(with event: NSEvent) {
        dragIsActive = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragIsActive, let draggingItemProvider else { return }
        do {
            guard let item = try draggingItemProvider(event) else { return }
            dragIsActive = true
            let session = beginDraggingSession(with: [item], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        } catch {
            draggingErrorHandler?(error)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        dragIsActive = false
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}

enum PreviewDragItemFactory {
    static let maximumThumbnailDimension: CGFloat = 180

    @MainActor
    static func makeFilePromiseProvider(
        image: NSImage,
        suggestedFilename: String,
        onWriteError: @escaping @MainActor () -> Void
    ) throws -> NSFilePromiseProvider {
        let promise = PreviewPromisedPNG(
            pngData: try RenderedImageExport.pngData(for: image),
            suggestedFilename: suggestedFilename,
            onWriteError: onWriteError
        )
        let provider = NSFilePromiseProvider(
            fileType: UTType.png.identifier,
            delegate: promise
        )
        // NSFilePromiseProvider keeps its delegate weakly. Retaining the immutable
        // generation payload in userInfo lets an accepted drop finish even if a
        // newer render replaces the image while the receiver writes the file.
        provider.userInfo = promise
        return provider
    }

    @MainActor
    static func makeDraggingItem(
        image: NSImage,
        suggestedFilename: String,
        location: NSPoint,
        onWriteError: @escaping @MainActor () -> Void
    ) throws -> NSDraggingItem {
        let provider = try makeFilePromiseProvider(
            image: image,
            suggestedFilename: suggestedFilename,
            onWriteError: onWriteError
        )
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(
            draggingFrame(imageSize: image.size, centeredAt: location),
            contents: image
        )
        return item
    }

    static func draggingFrame(
        imageSize: NSSize,
        centeredAt location: NSPoint
    ) -> NSRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return NSRect(
                x: location.x - maximumThumbnailDimension / 2,
                y: location.y - maximumThumbnailDimension / 2,
                width: maximumThumbnailDimension,
                height: maximumThumbnailDimension
            )
        }
        let scale = min(
            1,
            maximumThumbnailDimension / max(imageSize.width, imageSize.height)
        )
        let size = NSSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
        return NSRect(
            x: location.x - size.width / 2,
            y: location.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

final class PreviewPromisedPNG: NSObject, NSFilePromiseProviderDelegate {
    let filename: String
    private let pngData: Data
    private let onWriteError: @MainActor () -> Void
    private let writeQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "io.github.guangyya.md2png.preview-file-promise"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(
        pngData: Data,
        suggestedFilename: String,
        onWriteError: @escaping @MainActor () -> Void
    ) {
        self.pngData = pngData
        filename = Self.safeFilename(from: suggestedFilename)
        self.onWriteError = onWriteError
    }

    @MainActor
    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        filename
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            try pngData.write(to: url, options: .atomic)
            completionHandler(nil)
        } catch {
            completionHandler(AppError.pngWriteFailed)
            Task { @MainActor [onWriteError] in
                onWriteError()
            }
        }
    }

    @MainActor
    func operationQueue(
        for filePromiseProvider: NSFilePromiseProvider
    ) -> OperationQueue {
        writeQueue
    }

    private static func safeFilename(from suggestedFilename: String) -> String {
        let basename = (suggestedFilename as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !basename.isEmpty, basename != ".", basename != ".." else {
            return "md2png-render.png"
        }
        return basename.lowercased().hasSuffix(".png")
            ? basename
            : "\(basename).png"
    }
}
