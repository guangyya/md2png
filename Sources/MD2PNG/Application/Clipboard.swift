import AppKit

enum Clipboard {
    static var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    static func menuPreview(includeLabel: Bool = true) -> String {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)
        let hasImage = pasteboard.availableType(from: [.png, .tiff]) != nil
        return menuPreview(text: text, hasImage: hasImage, includeLabel: includeLabel)
    }

    static func menuPreview(
        text: String?,
        hasImage: Bool,
        maxCharacters: Int = 44,
        includeLabel: Bool = true,
        localizationBundle: Bundle? = nil
    ) -> String {
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
            return includeLabel
                ? L10n.format(
                    "clipboard.labeled",
                    defaultValue: "Clipboard: %@",
                    bundle: localizationBundle,
                    preview
                )
                : preview
        }

        if hasImage {
            let imageDescription = L10n.text(
                "clipboard.png_image",
                defaultValue: "PNG image",
                bundle: localizationBundle
            )
            return includeLabel
                ? L10n.format(
                    "clipboard.labeled",
                    defaultValue: "Clipboard: %@",
                    bundle: localizationBundle,
                    imageDescription
                )
                : imageDescription
        }

        let emptyDescription = L10n.text(
            "clipboard.no_text",
            defaultValue: "No text",
            bundle: localizationBundle
        )
        return includeLabel
            ? L10n.format(
                "clipboard.labeled",
                defaultValue: "Clipboard: %@",
                bundle: localizationBundle,
                emptyDescription
            )
            : emptyDescription
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
