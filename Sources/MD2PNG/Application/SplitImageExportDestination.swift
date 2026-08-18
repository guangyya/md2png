import AppKit

@MainActor
enum SplitImageExportDestination {
    static func choose(suggestedDirectoryName: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = L10n.text(
            "split_export.choose_folder_title",
            defaultValue: "Choose a Folder for Split PNGs"
        )
        panel.message = L10n.format(
            "split_export.choose_folder_message",
            defaultValue: "md2png will create a new “%@” folder containing numbered PNG files. Nothing will be copied to the clipboard.",
            suggestedDirectoryName
        )
        panel.prompt = L10n.text(
            "split_export.choose_folder_action",
            defaultValue: "Choose Folder"
        )
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let parentURL = panel.url else {
            return nil
        }
        return uniqueDestination(
            parentURL: parentURL,
            suggestedDirectoryName: suggestedDirectoryName
        )
    }

    static func uniqueDestination(
        parentURL: URL,
        suggestedDirectoryName: String,
        fileManager: FileManager = .default
    ) -> URL {
        let baseURL = parentURL.appendingPathComponent(
            suggestedDirectoryName,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: baseURL.path) else { return baseURL }
        for suffix in 2 ... 9_999 {
            let candidate = parentURL.appendingPathComponent(
                "\(suggestedDirectoryName)-\(suffix)",
                isDirectory: true
            )
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        let uniqueComponent = UUID().uuidString.prefix(8)
        return parentURL.appendingPathComponent(
            "\(suggestedDirectoryName)-\(uniqueComponent)",
            isDirectory: true
        )
    }
}
