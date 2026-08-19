import AppKit

typealias PreviewFileOpenCompletion = @Sendable (Bool) -> Void
typealias PreviewFileOpener = @MainActor (
    URL,
    @escaping PreviewFileOpenCompletion
) throws -> Void

enum PreviewWorkspaceOpener {
    static func open(
        _ url: URL,
        completion: @escaping PreviewFileOpenCompletion
    ) throws {
        guard let previewURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Preview"
        ) else {
            throw AppError.previewOpenFailed
        }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: previewURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            completion(error == nil)
        }
    }
}
