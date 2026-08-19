import AppKit

@MainActor
final class MarkdownFileServiceProvider: NSObject {
    static let filenamesPasteboardType = NSPasteboard.PasteboardType(
        "NSFilenamesPboardType"
    )

    private let onOpen: ([URL]) -> Void

    init(onOpen: @escaping ([URL]) -> Void) {
        self.onOpen = onOpen
        super.init()
    }

    @objc func previewWithMd2png(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        onOpen(Self.fileURLs(from: pasteboard))
    }

    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !objects.isEmpty {
            return objects
        }

        guard let paths = pasteboard.propertyList(
            forType: filenamesPasteboardType
        ) as? [String] else {
            return []
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }
}
