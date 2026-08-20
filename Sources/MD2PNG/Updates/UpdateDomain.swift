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

    var releasesURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/\(owner)/\(name)/releases"
        return components.url!
    }

    var appcastURL: URL {
        releasesURL
            .appendingPathComponent("latest")
            .appendingPathComponent("download")
            .appendingPathComponent("appcast.xml")
    }
}

enum UpdateError: LocalizedError, Equatable {
    case invalidInstalledVersion
    case networkUnavailable
    case rateLimited(retryAt: Date)
    case digestMismatch

    var errorDescription: String? {
        switch self {
        case .invalidInstalledVersion:
            return L10n.text(
                "update.error.installed_version",
                defaultValue: "The installed app version is not valid."
            )
        case .networkUnavailable:
            return L10n.text(
                "update.error.network",
                defaultValue: "The update service could not be reached. Check your connection and try again."
            )
        case let .rateLimited(retryAt):
            return L10n.format(
                "update.error.rate_limited",
                defaultValue: "GitHub temporarily limited update checks. Try again after %@.",
                retryAt.formatted(date: .omitted, time: .shortened)
            )
        case .digestMismatch:
            return L10n.text(
                "update.error.integrity",
                defaultValue: "The downloaded update did not pass its integrity check."
            )
        }
    }
}
