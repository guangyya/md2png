import AppKit

struct SplitImageExportDestinationPresentation: Equatable {
    let title: String
    let message: String
    let prompt: String

    static func make(
        suggestedDirectoryName: String,
        fileCount: Int,
        localizationBundle: Bundle? = nil
    ) -> SplitImageExportDestinationPresentation {
        let title = fileCount == 1
            ? L10n.text(
                "split_export.save_one_title",
                defaultValue: "Save 1 Split PNG",
                bundle: localizationBundle
            )
            : L10n.format(
                "split_export.save_many_title",
                defaultValue: "Save %ld Split PNGs",
                bundle: localizationBundle,
                fileCount
            )
        let message = fileCount == 1
            ? L10n.format(
                "split_export.save_one_message",
                defaultValue: "md2png will create a new “%@” folder containing 1 numbered PNG file. Nothing will be copied to the clipboard.",
                bundle: localizationBundle,
                suggestedDirectoryName
            )
            : L10n.format(
                "split_export.save_many_message",
                defaultValue: "md2png will create a new “%1$@” folder containing %2$ld numbered PNG files. Nothing will be copied to the clipboard.",
                bundle: localizationBundle,
                suggestedDirectoryName,
                fileCount
            )
        return SplitImageExportDestinationPresentation(
            title: title,
            message: message,
            prompt: L10n.text(
                "split_export.choose_folder_action",
                defaultValue: "Choose Folder",
                bundle: localizationBundle
            )
        )
    }
}

@MainActor
enum SplitImageExportDestination {
    static func choose(suggestedDirectoryName: String, fileCount: Int) -> URL? {
        let presentation = SplitImageExportDestinationPresentation.make(
            suggestedDirectoryName: suggestedDirectoryName,
            fileCount: fileCount
        )
        let panel = NSOpenPanel()
        panel.title = presentation.title
        panel.message = presentation.message
        panel.prompt = presentation.prompt
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
