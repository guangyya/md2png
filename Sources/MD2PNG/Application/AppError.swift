import Foundation

enum AppError: LocalizedError {
    case emptyClipboard
    case rendererUnavailable
    case rendererRecoveryFailed
    case rendererTimedOut
    case rendererFailed
    case invalidRendererResponse
    case contentTooLarge(width: Int, height: Int)
    case rendererPNGEncodingFailed
    case pngEncodingFailed
    case pngWriteFailed
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
