import Foundation

struct AppMetadata {
    static let sourceCommitInfoDictionaryKey = "MD2PNGSourceCommit"

    let version: String
    let build: String
    let sourceCommit: String?
    let buildConfiguration: AppBuildConfiguration
    let releaseNotes: String
    let projectURL: URL?

    init(
        version: String,
        build: String,
        sourceCommit: String? = nil,
        buildConfiguration: AppBuildConfiguration = .current,
        releaseNotes: String,
        projectURL: URL?
    ) {
        self.version = version
        self.build = build
        self.sourceCommit = Self.shortSourceCommit(from: sourceCommit)
        self.buildConfiguration = buildConfiguration
        self.releaseNotes = releaseNotes
        self.projectURL = projectURL
    }

    static func current(bundle: Bundle = .main) -> AppMetadata {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? L10n.text("about.development", defaultValue: "Development")
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let sourceCommit = bundle.object(
            forInfoDictionaryKey: sourceCommitInfoDictionaryKey
        ) as? String
        let notes: String

        if let changelogURL = AppResources.aboutChangelogURL(resourcesURL: bundle.resourceURL),
           let changelog = try? String(contentsOf: changelogURL, encoding: .utf8),
           let parsedNotes = ChangelogParser.releaseNotes(for: version, in: changelog) {
            notes = parsedNotes
        } else {
            notes = L10n.text(
                "about.release_notes_unavailable",
                defaultValue: "Release notes are not available in this build."
            )
        }

        return AppMetadata(
            version: version,
            build: build,
            sourceCommit: sourceCommit,
            buildConfiguration: .current,
            releaseNotes: notes,
            projectURL: ProjectLinks.project
        )
    }

    static func shortSourceCommit(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexadecimalCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard (7...64).contains(trimmedValue.count),
              trimmedValue.unicodeScalars.allSatisfy(hexadecimalCharacters.contains) else {
            return nil
        }
        return String(trimmedValue.prefix(7)).lowercased()
    }

    func versionBuildText(localizationBundle: Bundle? = nil) -> String {
        guard let sourceCommit else {
            return L10n.format(
                "about.version_build",
                defaultValue: "Version %@  •  Build %@",
                bundle: localizationBundle,
                version,
                build
            )
        }
        return L10n.format(
            "about.version_build_commit",
            defaultValue: "Version %@  •  Build %@  •  Commit %@",
            bundle: localizationBundle,
            version,
            build,
            sourceCommit
        )
    }

    func versionInfo(
        macOSVersion: String = AppRuntimeInfo.macOSVersion,
        architecture: String = AppRuntimeInfo.architecture,
        localizationBundle: Bundle? = nil
    ) -> String {
        let configuration = buildConfiguration.displayName(bundle: localizationBundle)
        if let sourceCommit {
            return L10n.format(
                "about.version_info_commit",
                defaultValue: "md2png %@ (%@) · commit %@ · %@ · macOS %@ · %@",
                bundle: localizationBundle,
                version,
                build,
                sourceCommit,
                configuration,
                macOSVersion,
                architecture
            )
        }
        return L10n.format(
            "about.version_info",
            defaultValue: "md2png %@ (%@) · %@ · macOS %@ · %@",
            bundle: localizationBundle,
            version,
            build,
            configuration,
            macOSVersion,
            architecture
        )
    }
}

enum AppRuntimeInfo {
    static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    static var architecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}

enum ChangelogParser {
    static func releaseNotes(
        for version: String,
        in changelog: String,
        localizationBundle: Bundle? = nil
    ) -> String? {
        let headingPrefix = "## [\(version)]"
        let lines = changelog.components(separatedBy: .newlines)
        guard let headingIndex = lines.firstIndex(where: { $0.hasPrefix(headingPrefix) }) else {
            return nil
        }

        let section = lines[(headingIndex + 1)...].prefix { !$0.hasPrefix("## [") }
        var blocks: [String] = []
        var currentBullet: String?

        func flushBullet() {
            if let currentBullet {
                blocks.append("• " + currentBullet)
            }
            currentBullet = nil
        }

        for rawLine in section {
            let line = rawLine.replacingOccurrences(of: "`", with: "")
            if rawLine.hasPrefix("### ") {
                flushBullet()
                blocks.append(localizedSectionHeading(
                    String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces),
                    bundle: localizationBundle
                ))
            } else if rawLine.hasPrefix("- ") {
                flushBullet()
                currentBullet = String(line.dropFirst(2))
                    .trimmingCharacters(in: .whitespaces)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                let continuation = line.trimmingCharacters(in: .whitespaces)
                if currentBullet != nil {
                    currentBullet! += " " + continuation
                } else {
                    blocks.append(continuation)
                }
            }
        }
        flushBullet()

        var formatted = ""
        for block in blocks {
            if formatted.isEmpty {
                formatted = block
            } else if !block.hasPrefix("• ") {
                formatted += "\n\n" + block
            } else {
                formatted += "\n" + block
            }
        }

        return formatted.isEmpty ? nil : formatted
    }

    private static func localizedSectionHeading(_ heading: String, bundle: Bundle?) -> String {
        let key: String
        switch heading {
        case "Added": key = "release_section.added"
        case "Changed": key = "release_section.changed"
        case "Fixed": key = "release_section.fixed"
        case "Removed": key = "release_section.removed"
        case "Deprecated": key = "release_section.deprecated"
        case "Security": key = "release_section.security"
        default: return heading
        }
        return L10n.text(key, defaultValue: heading, bundle: bundle)
    }
}
