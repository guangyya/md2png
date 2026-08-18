import AppKit

struct PreviewDraggingItem {
    let item: NSDraggingItem
    let exportID: UUID
}

@MainActor
final class PreviewDragImageView: NSImageView, NSDraggingSource {
    typealias DraggingItemProvider = (NSEvent) throws -> PreviewDraggingItem?

    var draggingItemProvider: DraggingItemProvider?
    var draggingSessionEnded: ((UUID, NSDragOperation) -> Void)?
    var draggingErrorHandler: ((Error) -> Void)?
    private var activeExportID: UUID?

    override func mouseDown(with event: NSEvent) {
        activeExportID = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard activeExportID == nil, let draggingItemProvider else { return }
        do {
            guard let draggingItem = try draggingItemProvider(event) else { return }
            activeExportID = draggingItem.exportID
            let session = beginDraggingSession(
                with: [draggingItem.item],
                event: event,
                source: self
            )
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
        guard let exportID = activeExportID else { return }
        activeExportID = nil
        draggingSessionEnded?(exportID, operation)
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}

struct PreviewDragExport {
    let id: UUID
    let fileURL: URL
    let pngData: Data
}

@MainActor
final class PreviewDragExportStore {
    private struct Record {
        let exportID: UUID
        let fileURL: URL
        let directoryURL: URL
        var hasAcceptedDrop = false
    }

    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private var recordsByGeneration: [UUID: Record] = [:]
    private var generationByExportID: [UUID: UUID] = [:]

    init(
        parentDirectoryURL: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        rootDirectoryURL = parentDirectoryURL.appendingPathComponent(
            "md2png-preview-drag-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    isolated deinit {
        try? fileManager.removeItem(at: rootDirectoryURL)
    }

    func export(
        image: NSImage,
        generationID: UUID,
        suggestedFilename: String
    ) throws -> PreviewDragExport {
        if let record = recordsByGeneration[generationID],
           fileManager.fileExists(atPath: record.fileURL.path),
           let pngData = try? Data(contentsOf: record.fileURL) {
            return PreviewDragExport(
                id: record.exportID,
                fileURL: record.fileURL,
                pngData: pngData
            )
        }
        if let replacedRecord = recordsByGeneration.removeValue(forKey: generationID) {
            generationByExportID.removeValue(forKey: replacedRecord.exportID)
            try? fileManager.removeItem(at: replacedRecord.directoryURL)
        }

        let pngData = try RenderedImageExport.pngData(for: image)
        let exportID = UUID()
        let directoryURL = rootDirectoryURL.appendingPathComponent(
            exportID.uuidString,
            isDirectory: true
        )
        let fileURL = directoryURL.appendingPathComponent(
            PreviewDragItemFactory.safeFilename(from: suggestedFilename),
            isDirectory: false
        )

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw AppError.pngWriteFailed
        }

        let export = PreviewDragExport(
            id: exportID,
            fileURL: fileURL,
            pngData: pngData
        )
        recordsByGeneration[generationID] = Record(
            exportID: export.id,
            fileURL: export.fileURL,
            directoryURL: directoryURL
        )
        generationByExportID[exportID] = generationID
        return export
    }

    func finishExport(_ exportID: UUID, operation: NSDragOperation) {
        guard let generationID = generationByExportID[exportID],
              var record = recordsByGeneration[generationID] else { return }
        guard record.exportID == exportID else {
            generationByExportID.removeValue(forKey: exportID)
            return
        }
        if !operation.isEmpty {
            record.hasAcceptedDrop = true
            recordsByGeneration[generationID] = record
        } else if !record.hasAcceptedDrop {
            removeRecord(generationID: generationID, record: record)
        }
    }

    func clear() {
        recordsByGeneration.removeAll()
        generationByExportID.removeAll()
        try? fileManager.removeItem(at: rootDirectoryURL)
    }

    private func removeRecord(generationID: UUID, record: Record) {
        recordsByGeneration.removeValue(forKey: generationID)
        generationByExportID.removeValue(forKey: record.exportID)
        try? fileManager.removeItem(at: record.directoryURL)
    }
}

enum PreviewDragItemFactory {
    static let maximumThumbnailDimension: CGFloat = 180

    static func makePasteboardItem(for export: PreviewDragExport) throws -> NSPasteboardItem {
        let item = NSPasteboardItem()
        guard item.setString(export.fileURL.absoluteString, forType: .fileURL),
              item.setData(export.pngData, forType: .png) else {
            throw AppError.pngWriteFailed
        }
        return item
    }

    @MainActor
    static func makeDraggingItem(
        export: PreviewDragExport,
        image: NSImage,
        location: NSPoint
    ) throws -> PreviewDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: try makePasteboardItem(for: export))
        item.setDraggingFrame(
            draggingFrame(imageSize: image.size, centeredAt: location),
            contents: image
        )
        return PreviewDraggingItem(item: item, exportID: export.id)
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

    static func safeFilename(from suggestedFilename: String) -> String {
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
