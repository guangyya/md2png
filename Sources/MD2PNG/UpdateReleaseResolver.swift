import Foundation

enum UpdateReleaseResolver {
    static let diskImageContentType = "application/x-apple-diskimage"

    static func resolve(
        release: UpdateRelease,
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
            asset.downloadURL,
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
            downloadURL: asset.downloadURL,
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
