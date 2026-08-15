import Foundation

struct SemanticVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        var normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("v") {
            normalized.removeFirst()
        }

        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }

        var parsed: [Int] = []
        for component in components {
            guard !component.isEmpty,
                  component.allSatisfy({ $0.isASCII && $0.isNumber }),
                  (component.count == 1 || component.first != "0"),
                  let value = Int(component) else {
                return nil
            }
            parsed.append(value)
        }

        major = parsed[0]
        minor = parsed[1]
        patch = parsed[2]
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct GitHubRepository: Equatable, Sendable {
    let owner: String
    let name: String

    init?(projectURL: URL) {
        guard let components = URLComponents(url: projectURL, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host?.caseInsensitiveCompare("github.com") == .orderedSame,
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }

        let pathComponents = projectURL.pathComponents.filter { $0 != "/" }
        guard pathComponents.count == 2,
              Self.isValidOwner(pathComponents[0]),
              Self.isValidRepositoryName(pathComponents[1]) else {
            return nil
        }
        owner = pathComponents[0]
        name = pathComponents[1]
    }

    private static func isValidOwner(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
        }
    }

    private static func isValidRepositoryName(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".")
        }
    }

    var latestReleaseAPIURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(owner)/\(name)/releases/latest"
        return components.url!
    }

    var releasesURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(owner)/\(name)/releases"
        return components.url!
    }
}

struct UpdateRelease: Codable, Equatable, Sendable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [UpdateReleaseAsset]
}

struct UpdateReleaseAsset: Codable, Equatable, Sendable {
    let name: String
    let contentType: String
    let size: Int64
    let digest: String?
    let downloadURL: URL
}

struct AvailableUpdate: Equatable, Sendable {
    let version: SemanticVersion
    let tagName: String
    let assetName: String
    let downloadURL: URL
    let size: Int64
    let sha256: String
}

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(installed: SemanticVersion, latest: SemanticVersion)
    case updateAvailable(AvailableUpdate)
}

enum UpdateError: LocalizedError, Equatable {
    case invalidInstalledVersion
    case unsupportedRepository
    case networkUnavailable
    case invalidServerResponse
    case httpStatus(Int)
    case rateLimited(retryAt: Date)
    case invalidRelease
    case invalidReleaseVersion
    case missingAsset
    case duplicateAsset
    case invalidAssetMetadata
    case insecureDownloadURL
    case cacheUnavailable
    case downloadFailed
    case fileSizeMismatch
    case digestMismatch
    case openFailed
    case revealFailed

    var errorDescription: String? {
        switch self {
        case .invalidInstalledVersion:
            return L10n.text(
                "update.error.installed_version",
                defaultValue: "The installed app version is not valid."
            )
        case .unsupportedRepository:
            return L10n.text(
                "update.error.repository",
                defaultValue: "This build does not contain a valid GitHub repository address."
            )
        case .networkUnavailable:
            return L10n.text(
                "update.error.network",
                defaultValue: "The update service could not be reached. Check your connection and try again."
            )
        case .invalidServerResponse:
            return L10n.text(
                "update.error.response",
                defaultValue: "GitHub returned an invalid update response."
            )
        case let .httpStatus(status):
            return L10n.format(
                "update.error.http",
                defaultValue: "The update request failed (HTTP %ld).",
                status
            )
        case let .rateLimited(retryAt):
            return L10n.format(
                "update.error.rate_limited",
                defaultValue: "GitHub temporarily limited update checks. Try again after %@.",
                retryAt.formatted(date: .omitted, time: .shortened)
            )
        case .invalidRelease, .invalidReleaseVersion:
            return L10n.text(
                "update.error.release",
                defaultValue: "The latest release has invalid version information."
            )
        case .missingAsset:
            return L10n.text(
                "update.error.asset_missing",
                defaultValue: "The latest release does not contain the expected Apple silicon DMG."
            )
        case .duplicateAsset, .invalidAssetMetadata, .insecureDownloadURL:
            return L10n.text(
                "update.error.asset_invalid",
                defaultValue: "The latest release contains invalid download metadata."
            )
        case .cacheUnavailable:
            return L10n.text(
                "update.error.cache",
                defaultValue: "The update could not be saved in the app cache."
            )
        case .downloadFailed:
            return L10n.text(
                "update.error.download",
                defaultValue: "The update could not be downloaded."
            )
        case .fileSizeMismatch, .digestMismatch:
            return L10n.text(
                "update.error.integrity",
                defaultValue: "The downloaded DMG did not pass its integrity check and was removed."
            )
        case .openFailed:
            return L10n.text(
                "update.error.open",
                defaultValue: "The downloaded DMG could not be opened."
            )
        case .revealFailed:
            return L10n.text(
                "update.error.reveal",
                defaultValue: "The downloaded DMG is no longer in the app cache. Download it again."
            )
        }
    }
}
