import AppKit

enum Clipboard {
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
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw AppError.emptyClipboard
        }
        return text
    }

    static func write(image: NSImage) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AppError.pngEncodingFailed
        }

        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
