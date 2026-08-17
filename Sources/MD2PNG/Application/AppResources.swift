import Foundation

enum ExampleKind: Int, CaseIterable {
    case short
    case long
    case formatting
    case code
    case checklist
    case table
    case flowchart
    case sequence
    case gantt

    var menuTitle: String {
        menuTitle(localizationBundle: nil)
    }

    func menuTitle(localizationBundle: Bundle?) -> String {
        switch self {
        case .short:
            return L10n.text(
                "example.short",
                defaultValue: "Short Example",
                bundle: localizationBundle
            )
        case .long:
            return L10n.text(
                "example.long",
                defaultValue: "Long Example",
                bundle: localizationBundle
            )
        case .formatting:
            return L10n.text(
                "example.formatting",
                defaultValue: "Formatting",
                bundle: localizationBundle
            )
        case .code:
            return L10n.text(
                "example.code",
                defaultValue: "Code Blocks",
                bundle: localizationBundle
            )
        case .checklist:
            return L10n.text(
                "example.checklist",
                defaultValue: "Checklist",
                bundle: localizationBundle
            )
        case .table:
            return L10n.text(
                "example.table",
                defaultValue: "GFM Table",
                bundle: localizationBundle
            )
        case .flowchart:
            return L10n.text(
                "example.flowchart",
                defaultValue: "Flowchart",
                bundle: localizationBundle
            )
        case .sequence:
            return L10n.text(
                "example.sequence",
                defaultValue: "Sequence Diagram",
                bundle: localizationBundle
            )
        case .gantt:
            return L10n.text(
                "example.gantt",
                defaultValue: "Gantt Timeline",
                bundle: localizationBundle
            )
        }
    }

    var fileName: String {
        switch self {
        case .short:
            return "weekly-update.md"
        case .long:
            return "long-project-update.md"
        case .formatting:
            return "formatting.md"
        case .code:
            return "code-blocks.md"
        case .checklist:
            return "checklist.md"
        case .table:
            return "table.md"
        case .flowchart:
            return "flowchart.md"
        case .sequence:
            return "sequence-diagram.md"
        case .gantt:
            return "gantt-timeline.md"
        }
    }

    var startsMenuSection: Bool {
        self == .formatting || self == .flowchart
    }
}

enum ProjectLinks {
    static let infoDictionaryKey = "MD2PNGProjectURL"

    static var project: URL? {
        projectURL(bundle: .main)
    }

    static var releases: URL? {
        project.map(releasesURL(for:))
    }

    static var githubRepository: GitHubRepository? {
        project.flatMap(GitHubRepository.init(projectURL:))
    }

    static func projectURL(bundle: Bundle) -> URL? {
        projectURL(from: bundle.object(forInfoDictionaryKey: infoDictionaryKey))
    }

    static func projectURL(from configuredValue: Any?) -> URL? {
        guard let configuredValue = configuredValue as? String else { return nil }
        let trimmedValue = configuredValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              let components = URLComponents(string: trimmedValue),
              components.scheme == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let url = components.url else {
            return nil
        }
        return url
    }

    static func releasesURL(for projectURL: URL) -> URL {
        projectURL.appendingPathComponent("releases", isDirectory: false)
    }
}

enum AppResources {
    static func exampleURL(
        for kind: ExampleKind,
        resourcesURL: URL?,
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) -> URL? {
        let candidates = [
            resourcesURL?
                .appendingPathComponent("Examples", isDirectory: true)
                .appendingPathComponent(kind.fileName),
            currentDirectoryURL
                .appendingPathComponent("Examples", isDirectory: true)
                .appendingPathComponent(kind.fileName)
        ]

        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    static func exampleMarkdown(for kind: ExampleKind) throws -> String {
        guard let url = exampleURL(for: kind, resourcesURL: Bundle.main.resourceURL) else {
            throw AppError.exampleUnavailable(kind.menuTitle)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AppError.exampleUnavailable(kind.menuTitle)
        }
    }

    static func aboutChangelogURL(
        resourcesURL: URL?,
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) -> URL? {
        let candidates = [
            resourcesURL?.appendingPathComponent("ABOUT_CHANGELOG.md"),
            currentDirectoryURL.appendingPathComponent("ABOUT_CHANGELOG.md")
        ]

        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}
