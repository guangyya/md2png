import Foundation

struct SeamlessUpdateReleaseNotes: Equatable, Sendable {
    let version: String
    let publishedAt: Date?
    let text: String?
}

struct SeamlessUpdate: Equatable, Sendable {
    let installedVersion: String
    let displayVersion: String
    let buildVersion: String
    let publishedAt: Date?
    let contentLength: UInt64?
    let releaseNotes: [SeamlessUpdateReleaseNotes]
    let historyIsTruncated: Bool
    let fullReleaseNotesURL: URL?
}

struct SeamlessUpdateAppcastEntry: Equatable, Sendable {
    let displayVersion: String
    let buildVersion: String
    let publishedAt: Date?
    let contentLength: UInt64?
    let releaseNotes: String?
    let fullReleaseNotesURL: URL?
}

enum SeamlessUpdateMetadataBuilder {
    static let maximumVisibleReleases = 3

    static func make(
        installedVersion: String,
        selectedBuildVersion: String,
        entries: [SeamlessUpdateAppcastEntry]
    ) -> SeamlessUpdate? {
        guard let installed = SemanticVersion(installedVersion),
              let selectedEntry = entries.first(where: {
                  $0.buildVersion == selectedBuildVersion
              }),
              let selected = SemanticVersion(selectedEntry.displayVersion),
              selected > installed else {
            return nil
        }

        let eligibleEntries = entries
            .compactMap { entry -> (SemanticVersion, SeamlessUpdateAppcastEntry)? in
                guard let version = SemanticVersion(entry.displayVersion),
                      version > installed,
                      version <= selected else {
                    return nil
                }
                return (version, entry)
            }
            .reduce(into: [String: (SemanticVersion, SeamlessUpdateAppcastEntry)]()) {
                result, pair in
                if result[pair.1.displayVersion] == nil {
                    result[pair.1.displayVersion] = pair
                }
            }
            .map(\.value)
            .sorted { $0.0 > $1.0 }

        guard eligibleEntries.contains(where: {
            $0.1.buildVersion == selectedBuildVersion
        }) else {
            return nil
        }

        let visibleEntries = eligibleEntries.prefix(maximumVisibleReleases)
        let oldestFeedVersion = entries.compactMap {
            SemanticVersion($0.displayVersion)
        }.min()
        let feedReachedHistoryLimit = entries.count >= maximumVisibleReleases
        let omittedByVisibleLimit = eligibleEntries.count > maximumVisibleReleases
        let omittedBeforeFeed = feedReachedHistoryLimit
            && oldestFeedVersion.map { installed < $0 } == true

        let releaseNotes = visibleEntries.map { _, entry in
            SeamlessUpdateReleaseNotes(
                version: entry.displayVersion,
                publishedAt: entry.publishedAt,
                text: entry.releaseNotes.flatMap(
                    SeamlessReleaseNotesSanitizer.sanitize
                )
            )
        }

        return SeamlessUpdate(
            installedVersion: installedVersion,
            displayVersion: selectedEntry.displayVersion,
            buildVersion: selectedEntry.buildVersion,
            publishedAt: selectedEntry.publishedAt,
            contentLength: selectedEntry.contentLength.flatMap { $0 > 0 ? $0 : nil },
            releaseNotes: releaseNotes,
            historyIsTruncated: omittedByVisibleLimit || omittedBeforeFeed,
            fullReleaseNotesURL: selectedEntry.fullReleaseNotesURL
        )
    }
}

enum SeamlessReleaseNotesSanitizer {
    static let maximumInputBytes = 24 * 1_024
    static let maximumLines = 240
    static let maximumLineCharacters = 1_000

    static func sanitize(_ source: String) -> String? {
        let boundedSource = String(
            decoding: source.utf8.prefix(maximumInputBytes),
            as: UTF8.self
        )
        let normalized = boundedSource
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var output: [String] = []
        var insideCodeFence = false

        for rawLine in normalized.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).prefix(maximumLines) {
            var line = String(rawLine.prefix(maximumLineCharacters))
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideCodeFence.toggle()
                continue
            }

            line = stripHTMLTags(from: line)
            line = line.replacingOccurrences(
                of: #"!\[([^\]]*)\]\([^\n)]*\)"#,
                with: "$1",
                options: .regularExpression
            )
            line = line.replacingOccurrences(
                of: #"\[([^\]]+)\]\([^\n)]*\)"#,
                with: "$1",
                options: .regularExpression
            )
            line = line.replacingOccurrences(
                of: #"^\s{0,3}#{1,6}\s+"#,
                with: "",
                options: .regularExpression
            )
            line = line.replacingOccurrences(of: "`", with: "")
            if insideCodeFence {
                line = "    " + line
            }
            output.append(line.trimmingCharacters(in: .whitespaces))
        }

        let result = collapseBlankLines(in: output)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func stripHTMLTags(from source: String) -> String {
        source.replacingOccurrences(
            of: #"<\/?[A-Za-z!][^>]*>"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func collapseBlankLines(in lines: [String]) -> [String] {
        var result: [String] = []
        var previousWasBlank = false
        for line in lines {
            let isBlank = line.isEmpty
            if !isBlank || !previousWasBlank {
                result.append(line)
            }
            previousWasBlank = isBlank
        }
        return result
    }
}

enum SeamlessUpdateLinkPolicy {
    static func trustedReleaseNotesURL(_ candidate: URL?, feedURL: URL?) -> URL? {
        guard let candidate,
              let feedURL,
              let candidateComponents = URLComponents(
                url: candidate,
                resolvingAgainstBaseURL: false
              ),
              let feedComponents = URLComponents(
                url: feedURL,
                resolvingAgainstBaseURL: false
              ),
              candidateComponents.scheme == "https",
              feedComponents.scheme == "https",
              candidateComponents.host?.caseInsensitiveCompare("github.com") == .orderedSame,
              feedComponents.host?.caseInsensitiveCompare("github.com") == .orderedSame,
              candidateComponents.port == nil,
              candidateComponents.user == nil,
              candidateComponents.password == nil,
              candidateComponents.query == nil,
              candidateComponents.fragment == nil else {
            return nil
        }
        let candidatePath = candidate.pathComponents.filter { $0 != "/" }
        let feedPath = feedURL.pathComponents.filter { $0 != "/" }
        guard candidatePath.count >= 3,
              feedPath.count >= 2,
              candidatePath[0] == feedPath[0],
              candidatePath[1] == feedPath[1],
              candidatePath[2] == "releases" else {
            return nil
        }
        return candidate
    }
}
