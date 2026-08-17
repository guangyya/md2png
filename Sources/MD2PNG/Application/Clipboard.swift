import AppKit

struct ClipboardMenuState: Equatable {
    let preview: String
    let containsMarkdown: Bool
}

enum Clipboard {
    static var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    static func menuPreview(includeLabel: Bool = true) -> String {
        menuState(includeLabel: includeLabel).preview
    }

    static func menuState(includeLabel: Bool = true) -> ClipboardMenuState {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)
        let hasImage = pasteboard.availableType(from: [.png, .tiff]) != nil
        return menuState(text: text, hasImage: hasImage, includeLabel: includeLabel)
    }

    static func menuPreview(
        text: String?,
        hasImage: Bool,
        maxCharacters: Int = 44,
        includeLabel: Bool = true,
        localizationBundle: Bundle? = nil
    ) -> String {
        menuState(
            text: text,
            hasImage: hasImage,
            maxCharacters: maxCharacters,
            includeLabel: includeLabel,
            localizationBundle: localizationBundle
        ).preview
    }

    static func menuState(
        text: String?,
        hasImage: Bool,
        maxCharacters: Int = 44,
        includeLabel: Bool = true,
        localizationBundle: Bundle? = nil
    ) -> ClipboardMenuState {
        let normalizedText = text?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ") ?? ""

        if !normalizedText.isEmpty {
            let preview: String
            if normalizedText.count > maxCharacters {
                preview = String(normalizedText.prefix(maxCharacters - 1)) + "…"
            } else {
                preview = normalizedText
            }
            return ClipboardMenuState(
                preview: includeLabel
                ? L10n.format(
                    "clipboard.labeled",
                    defaultValue: "Clipboard: %@",
                    bundle: localizationBundle,
                    preview
                )
                : preview,
                containsMarkdown: true
            )
        }

        if hasImage {
            let imageDescription = L10n.text(
                "clipboard.png_image",
                defaultValue: "PNG image",
                bundle: localizationBundle
            )
            return ClipboardMenuState(
                preview: includeLabel
                ? L10n.format(
                    "clipboard.labeled",
                    defaultValue: "Clipboard: %@",
                    bundle: localizationBundle,
                    imageDescription
                )
                : imageDescription,
                containsMarkdown: false
            )
        }

        let emptyDescription = L10n.text(
            "clipboard.no_text",
            defaultValue: "No text",
            bundle: localizationBundle
        )
        return ClipboardMenuState(
            preview: includeLabel
            ? L10n.format(
                "clipboard.labeled",
                defaultValue: "Clipboard: %@",
                bundle: localizationBundle,
                emptyDescription
            )
            : emptyDescription,
            containsMarkdown: false
        )
    }

    static func markdownText() throws -> String {
        try markdownText(from: NSPasteboard.general.string(forType: .string))
    }

    static func markdownText(from clipboardText: String?) throws -> String {
        guard let clipboardText,
              !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.emptyClipboard
        }
        return clipboardText
    }

    @discardableResult
    static func write(image: NSImage) throws -> Int {
        guard let tiff = image.tiffRepresentation else {
            throw AppError.pngEncodingFailed
        }
        let png = try RenderedImageExport.pngData(for: image)

        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png),
              item.setData(tiff, forType: .tiff) else {
            throw AppError.clipboardWriteFailed
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw AppError.clipboardWriteFailed
        }
        return pasteboard.changeCount
    }

    @discardableResult
    static func write(markdown: String) throws -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(markdown, forType: .string) else {
            throw AppError.clipboardWriteFailed
        }
        return pasteboard.changeCount
    }
}
