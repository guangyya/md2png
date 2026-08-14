import CryptoKit
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

struct GitHubRelease: Codable, Equatable, Sendable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }
}

struct GitHubReleaseAsset: Codable, Equatable, Sendable {
    let name: String
    let contentType: String
    let size: Int64
    let digest: String?
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case contentType = "content_type"
        case size
        case digest
        case browserDownloadURL = "browser_download_url"
    }
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

struct GitHubRateLimitInfo: Equatable, Sendable {
    let remaining: Int?
    let resetAt: Date?
}

struct UpdateCheckResponse: Equatable, Sendable {
    let result: UpdateCheckResult
    let release: GitHubRelease
    let rateLimit: GitHubRateLimitInfo
}

enum UpdateDownloadEvent: Equatable, Sendable {
    case progress(received: Int64, expected: Int64)
    case verifying
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

enum UpdateReleaseResolver {
    static let diskImageContentType = "application/x-apple-diskimage"

    static func resolve(
        release: GitHubRelease,
        repository: GitHubRepository,
        installedVersionString: String
    ) throws -> UpdateCheckResult {
        guard let installedVersion = SemanticVersion(installedVersionString) else {
            throw UpdateError.invalidInstalledVersion
        }
        guard !release.draft, !release.prerelease else {
            throw UpdateError.invalidRelease
        }
        guard let latestVersion = SemanticVersion(release.tagName) else {
            throw UpdateError.invalidReleaseVersion
        }
        guard latestVersion > installedVersion else {
            return .upToDate(installed: installedVersion, latest: latestVersion)
        }

        let expectedName = "md2png-\(latestVersion)-macOS-arm64-developer-id.dmg"
        let matches = release.assets.filter { $0.name == expectedName }
        guard !matches.isEmpty else { throw UpdateError.missingAsset }
        guard matches.count == 1, let asset = matches.first else {
            throw UpdateError.duplicateAsset
        }
        guard asset.contentType == diskImageContentType,
              asset.size > 0,
              let digest = normalizedSHA256(asset.digest) else {
            throw UpdateError.invalidAssetMetadata
        }
        guard isExpectedDownloadURL(
            asset.browserDownloadURL,
            repository: repository,
            tagName: release.tagName,
            assetName: expectedName
        ) else {
            throw UpdateError.insecureDownloadURL
        }

        return .updateAvailable(AvailableUpdate(
            version: latestVersion,
            tagName: release.tagName,
            assetName: expectedName,
            downloadURL: asset.browserDownloadURL,
            size: asset.size,
            sha256: digest
        ))
    }

    static func normalizedSHA256(_ digest: String?) -> String? {
        guard let digest else { return nil }
        let parts = digest.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].lowercased() == "sha256",
              parts[1].count == 64,
              parts[1].allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return parts[1].lowercased()
    }

    private static func isExpectedDownloadURL(
        _ url: URL,
        repository: GitHubRepository,
        tagName: String,
        assetName: String
    ) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https",
              components.host?.caseInsensitiveCompare("github.com") == .orderedSame,
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return false
        }
        return url.path == "/\(repository.owner)/\(repository.name)/releases/download/\(tagName)/\(assetName)"
    }
}

private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Int64, Int64) -> Void

    init(progressHandler: @escaping @Sendable (Int64, Int64) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progressHandler(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}

final class UpdateService: @unchecked Sendable {
    private let session: URLSession
    private let cacheDirectoryOverride: URL?

    init(session: URLSession = UpdateService.makeSession(), cacheDirectory: URL? = nil) {
        self.session = session
        cacheDirectoryOverride = cacheDirectory
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    func checkForUpdate(
        repository: GitHubRepository,
        installedVersion: String,
        now: Date = Date()
    ) async throws -> UpdateCheckResponse {
        var request = URLRequest(url: repository.latestReleaseAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("md2png-update-check/\(installedVersion)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            if Task.isCancelled { throw CancellationError() }
            throw UpdateError.networkUnavailable
        } catch {
            throw UpdateError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidServerResponse
        }
        if httpResponse.statusCode == 403 || httpResponse.statusCode == 429 {
            throw UpdateError.rateLimited(retryAt: Self.retryDate(
                from: httpResponse,
                now: now
            ))
        }
        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpStatus(httpResponse.statusCode)
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateError.invalidServerResponse
        }
        let result = try UpdateReleaseResolver.resolve(
            release: release,
            repository: repository,
            installedVersionString: installedVersion
        )
        return UpdateCheckResponse(
            result: result,
            release: release,
            rateLimit: GitHubRateLimitInfo(
                remaining: Int(httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? ""),
                resetAt: Self.rateLimitResetDate(from: httpResponse)
            )
        )
    }

    private static func retryDate(from response: HTTPURLResponse, now: Date) -> Date {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(retryAfter), seconds >= 0 {
                return now.addingTimeInterval(seconds)
            }
            for format in [
                "EEE',' dd MMM yyyy HH':'mm':'ss z",
                "EEEE',' dd-MMM-yy HH':'mm':'ss z",
                "EEE MMM d HH':'mm':'ss yyyy"
            ] {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                if let date = formatter.date(from: retryAfter) {
                    return max(date, now)
                }
            }
        }
        if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
           let resetAt = rateLimitResetDate(from: response) {
            return max(resetAt, now)
        }
        return now.addingTimeInterval(60)
    }

    private static func rateLimitResetDate(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let seconds = TimeInterval(value) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    func download(
        _ update: AvailableUpdate,
        eventHandler: @escaping @Sendable (UpdateDownloadEvent) -> Void
    ) async throws -> URL {
        let cacheDirectory = try updateCacheDirectory()
        let destinationURL = cacheDirectory.appendingPathComponent(update.assetName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            do {
                eventHandler(.progress(received: update.size, expected: update.size))
                eventHandler(.verifying)
                try Self.verifyFile(at: destinationURL, update: update)
                return destinationURL
            } catch {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }

        try removePartialDownloads(in: cacheDirectory)
        var request = URLRequest(url: update.downloadURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 300
        request.setValue("md2png-update-download/\(update.version)", forHTTPHeaderField: "User-Agent")
        let delegate = UpdateDownloadDelegate { received, expected in
            eventHandler(.progress(
                received: received,
                expected: expected > 0 ? expected : update.size
            ))
        }

        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await session.download(for: request, delegate: delegate)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            if Task.isCancelled { throw CancellationError() }
            throw UpdateError.downloadFailed
        } catch {
            throw UpdateError.downloadFailed
        }
        try Task.checkCancellation()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidServerResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpStatus(httpResponse.statusCode)
        }

        let partialURL = cacheDirectory.appendingPathComponent(
            ".md2png-update-\(UUID().uuidString).download"
        )
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
        } catch {
            throw UpdateError.cacheUnavailable
        }
        defer { try? FileManager.default.removeItem(at: partialURL) }

        eventHandler(.progress(received: update.size, expected: update.size))
        eventHandler(.verifying)
        try Self.verifyFile(at: partialURL, update: update)
        try Task.checkCancellation()
        do {
            try FileManager.default.moveItem(at: partialURL, to: destinationURL)
        } catch {
            throw UpdateError.cacheUnavailable
        }
        return destinationURL
    }

    static func verifyFile(at fileURL: URL, update: AvailableUpdate) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value == update.size else {
            throw UpdateError.fileSizeMismatch
        }
        guard try sha256(for: fileURL) == update.sha256 else {
            throw UpdateError.digestMismatch
        }
    }

    static func sha256(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func updateCacheDirectory() throws -> URL {
        let directory: URL
        if let cacheDirectoryOverride {
            directory = cacheDirectoryOverride
        } else {
            guard let cachesDirectory = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first else {
                throw UpdateError.cacheUnavailable
            }
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.guangyya.md2png"
            directory = cachesDirectory
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
                .appendingPathComponent("Updates", isDirectory: true)
        }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            throw UpdateError.cacheUnavailable
        }
    }

    private func removePartialDownloads(in directory: URL) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for url in contents where url.lastPathComponent.hasPrefix(".md2png-update-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
