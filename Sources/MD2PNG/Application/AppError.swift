import Foundation

enum AppError: LocalizedError {
    case emptyClipboard
    case unsupportedMarkdownFileType
    case markdownFileReadFailed
    case markdownFileInvalidEncoding
    case emptyMarkdownFile
    case rendererUnavailable
    case rendererRecoveryFailed
    case rendererTimedOut
    case rendererFailed
    case invalidRendererResponse
    case contentTooLarge(width: Int, height: Int)
    case splitExportContentTooLarge(width: Int, height: Int)
    case rendererPNGEncodingFailed
    case pngEncodingFailed
    case pngWriteFailed
    case splitExportWriteFailed
    case previewOpenFailed
    case clipboardWriteFailed
    case exampleUnavailable(String)

    var errorDescription: String? {
        message()
    }

    func message(localizationBundle: Bundle? = nil) -> String {
        switch self {
        case .emptyClipboard:
            return L10n.text(
                "error.empty_clipboard",
                defaultValue: "No Markdown to render. Copy Markdown, then try again.",
                bundle: localizationBundle
            )
        case .unsupportedMarkdownFileType:
            return L10n.text(
                "error.unsupported_markdown_file_type",
                defaultValue: "Choose a .md, .markdown, or .txt file. The clipboard is unchanged.",
                bundle: localizationBundle
            )
        case .markdownFileReadFailed:
            return L10n.text(
                "error.markdown_file_read_failed",
                defaultValue: "Couldn’t read the selected file. The clipboard is unchanged. Check its permissions and try again.",
                bundle: localizationBundle
            )
        case .markdownFileInvalidEncoding:
            return L10n.text(
                "error.markdown_file_invalid_encoding",
                defaultValue: "The selected file isn’t valid UTF-8. The clipboard is unchanged. Save it as UTF-8 and try again.",
                bundle: localizationBundle
            )
        case .emptyMarkdownFile:
            return L10n.text(
                "error.empty_markdown_file",
                defaultValue: "The selected file has no Markdown to render. The clipboard is unchanged.",
                bundle: localizationBundle
            )
        case .rendererUnavailable:
            return L10n.text(
                "error.renderer_unavailable",
                defaultValue: "Couldn’t render the Markdown. The clipboard is unchanged. Reopen md2png, then try again.",
                bundle: localizationBundle
            )
        case .rendererRecoveryFailed:
            return L10n.text(
                "error.renderer_recovery_failed",
                defaultValue: "Couldn’t render the Markdown. The clipboard is unchanged. Try again; if it still fails, reopen md2png.",
                bundle: localizationBundle
            )
        case .rendererTimedOut:
            return L10n.text(
                "error.renderer_timed_out",
                defaultValue: "Rendering took too long. The clipboard is unchanged. Shorten the Markdown and try again.",
                bundle: localizationBundle
            )
        case .rendererFailed:
            return L10n.text(
                "error.renderer_failed",
                defaultValue: "Couldn’t render the Markdown. The clipboard is unchanged. Check the Markdown and try again.",
                bundle: localizationBundle
            )
        case .invalidRendererResponse:
            return L10n.text(
                "error.invalid_renderer_response",
                defaultValue: "Couldn’t create the PNG. The clipboard is unchanged. Try rendering again.",
                bundle: localizationBundle
            )
        case let .contentTooLarge(width, height):
            return L10n.format(
                "error.content_too_large",
                defaultValue: "Couldn’t create a %1$ld × %2$ld PNG. The clipboard is unchanged. Shorten the Markdown and try again.",
                bundle: localizationBundle,
                width,
                height
            )
        case let .splitExportContentTooLarge(width, height):
            return L10n.format(
                "error.split_export_content_too_large",
                defaultValue: "Couldn’t split a %1$ld × %2$ld render within the safe export limit. The clipboard is unchanged. Shorten the Markdown and try again.",
                bundle: localizationBundle,
                width,
                height
            )
        case .rendererPNGEncodingFailed:
            return L10n.text(
                "error.renderer_png_encoding_failed",
                defaultValue: "Couldn’t create the PNG. The clipboard is unchanged. Try rendering again.",
                bundle: localizationBundle
            )
        case .pngEncodingFailed:
            return L10n.text(
                "error.png_encoding_failed",
                defaultValue: "Couldn’t prepare the PNG. Render it again, then retry.",
                bundle: localizationBundle
            )
        case .pngWriteFailed:
            return L10n.text(
                "error.png_write_failed",
                defaultValue: "Couldn’t save the PNG. Choose another location and try again.",
                bundle: localizationBundle
            )
        case .splitExportWriteFailed:
            return L10n.text(
                "error.split_export_write_failed",
                defaultValue: "Couldn’t save the split PNGs. Choose another folder and try again.",
                bundle: localizationBundle
            )
        case .previewOpenFailed:
            return L10n.text(
                "error.preview_open_failed",
                defaultValue: "Couldn’t open the PNG in Preview. Save it, then open it manually.",
                bundle: localizationBundle
            )
        case .clipboardWriteFailed:
            return L10n.text(
                "error.clipboard_write_failed",
                defaultValue: "Couldn’t update the clipboard. Copy the Markdown again, then retry.",
                bundle: localizationBundle
            )
        case let .exampleUnavailable(name):
            return L10n.format(
                "error.example_unavailable",
                defaultValue: "Couldn’t load %@. Choose another Example and try again.",
                bundle: localizationBundle,
                name
            )
        }
    }
}
