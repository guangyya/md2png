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
        panel.title = presentation.title
        panel.message = presentation.message
        panel.prompt = presentation.prompt
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = MarkdownFileInput.supportedFilenameExtensions
            .compactMap { UTType(filenameExtension: $0) }
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum MarkdownFileInput {
    static let supportedFilenameExtensions = ["md", "markdown", "txt"]
    private static let utf8ByteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    static func load(
        from fileURL: URL,
        readData: (URL) throws -> Data = {
            try Data(contentsOf: $0, options: .mappedIfSafe)
        }
    ) throws -> String {
        guard fileURL.isFileURL,
              supportedFilenameExtensions.contains(fileURL.pathExtension.lowercased()) else {
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
