import Foundation

enum AppError: LocalizedError {
    case emptyClipboard
    case rendererUnavailable
    case rendererRecoveryFailed
    case rendererTimedOut
    case invalidRendererResponse
    case contentTooLarge(width: Int, height: Int)
    case pngEncodingFailed
    case clipboardWriteFailed
    case exampleUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyClipboard:
            return L10n.text(
                "error.empty_clipboard",
                defaultValue: "The clipboard does not contain Markdown text. Copy some Markdown and try again."
            )
        case .rendererUnavailable:
            return L10n.text(
                "error.renderer_unavailable",
                defaultValue: "The local renderer could not be loaded."
            )
        case .rendererRecoveryFailed:
            return L10n.text(
                "error.renderer_recovery_failed",
                defaultValue: "The local renderer stopped and could not recover. Try rendering again."
            )
        case .rendererTimedOut:
            return L10n.text(
                "error.renderer_timed_out",
                defaultValue: "The local renderer took too long to respond. Try rendering again."
            )
        case .invalidRendererResponse:
            return L10n.text(
                "error.invalid_renderer_response",
                defaultValue: "The renderer returned an invalid image size."
            )
        case let .contentTooLarge(width, height):
            return L10n.format(
                "error.content_too_large",
                defaultValue: "The rendered content is too large (%ld × %ld). Try a shorter selection.",
                width,
                height
            )
        case .pngEncodingFailed:
            return L10n.text(
                "error.png_encoding_failed",
                defaultValue: "The rendered image could not be encoded as PNG."
            )
        case .clipboardWriteFailed:
            return L10n.text(
                "error.clipboard_write_failed",
                defaultValue: "The clipboard could not be updated."
            )
        case let .exampleUnavailable(name):
            return L10n.format(
                "error.example_unavailable",
                defaultValue: "The %@ Markdown file could not be loaded.",
                name
            )
        }
    }
}
