import AppKit
import UniformTypeIdentifiers

struct MarkdownFilePickerPresentation: Equatable {
    let title: String
    let message: String
    let prompt: String

    static func make(
        localizationBundle: Bundle? = nil
    ) -> MarkdownFilePickerPresentation {
        MarkdownFilePickerPresentation(
            title: L10n.text(
                "file_import.title",
                defaultValue: "Render Markdown File",
                bundle: localizationBundle
            ),
            message: L10n.text(
                "file_import.message",
                defaultValue: "Choose a Markdown or plain-text file to render locally.",
                bundle: localizationBundle
            ),
            prompt: L10n.text(
                "file_import.prompt",
                defaultValue: "Render",
                bundle: localizationBundle
            )
        )
    }
}

@MainActor
enum MarkdownFilePicker {
    static func choose() -> URL? {
        let presentation = MarkdownFilePickerPresentation.make()
        let panel = NSOpenPanel()
        let delegate = MarkdownFilePickerDelegate()
        panel.title = presentation.title
        panel.message = presentation.message
        panel.prompt = presentation.prompt
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowsOtherFileTypes = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = MarkdownFileInput.supportedFilenameExtensions
            .compactMap { UTType(filenameExtension: $0) }
        panel.delegate = delegate
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
final class MarkdownFilePickerDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        if url.hasDirectoryPath ||
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            return true
        }
        return MarkdownFileInput.supports(fileURL: url)
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard MarkdownFileInput.supports(fileURL: url) else {
            throw AppError.unsupportedMarkdownFileType
        }
    }
}

enum MarkdownFileInput {
    static let supportedFilenameExtensions = ["md", "markdown", "txt"]
    private static let utf8ByteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    static func supports(fileURL: URL) -> Bool {
        fileURL.isFileURL && supportedFilenameExtensions.contains(
            fileURL.pathExtension.lowercased()
        )
    }

    static func load(
        from fileURL: URL,
        readData: (URL) throws -> Data = {
            try Data(contentsOf: $0, options: .mappedIfSafe)
        }
    ) throws -> String {
        guard supports(fileURL: fileURL) else {
            throw AppError.unsupportedMarkdownFileType
        }

        let data: Data
        do {
            data = try readData(fileURL)
        } catch {
            throw AppError.markdownFileReadFailed
        }

        let contentBytes = data.starts(with: utf8ByteOrderMark)
            ? data.dropFirst(utf8ByteOrderMark.count)
            : data[...]
        guard let markdown = String(bytes: contentBytes, encoding: .utf8) else {
            throw AppError.markdownFileInvalidEncoding
        }
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.emptyMarkdownFile
        }
        return markdown
    }
}

enum MarkdownFileOpenRequest {
    static func singleFileURL(from urls: [URL]) throws -> URL {
        guard urls.count == 1, let fileURL = urls.first else {
            throw AppError.multipleMarkdownFilesUnsupported
        }
        return fileURL
    }
}
