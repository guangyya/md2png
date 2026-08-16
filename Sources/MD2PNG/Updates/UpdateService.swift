import Foundation

enum UpdateNetworkSession {
    static func make() -> URLSession {
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
}

struct UpdateCheckResponse: Equatable, Sendable {
    let result: UpdateCheckResult
    let release: UpdateRelease
    let rateLimit: GitHubRateLimitInfo
}

final class UpdateService: @unchecked Sendable {
    private let metadataClient: GitHubReleaseMetadataClient
    private let artifactDownloader: UpdateArtifactDownloader

    init(session: URLSession = UpdateService.makeSession(), cacheDirectory: URL? = nil) {
        metadataClient = GitHubReleaseMetadataClient(session: session)
        artifactDownloader = UpdateArtifactDownloader(
            session: session,
            cache: UpdateArtifactCache(directory: cacheDirectory)
        )
    }

    init(
        metadataClient: GitHubReleaseMetadataClient,
        artifactDownloader: UpdateArtifactDownloader
    ) {
        self.metadataClient = metadataClient
        self.artifactDownloader = artifactDownloader
    }

    static func makeSession() -> URLSession {
        UpdateNetworkSession.make()
    }

    func checkForUpdate(
        repository: GitHubRepository,
        installedVersion: String,
        now: Date = Date()
    ) async throws -> UpdateCheckResponse {
        let metadata = try await metadataClient.fetchLatestRelease(
            repository: repository,
            userAgentVersion: installedVersion,
            now: now
        )
        let result = try UpdateReleaseResolver.resolve(
            release: metadata.release,
            repository: repository,
            installedVersionString: installedVersion
        )
        return UpdateCheckResponse(
            result: result,
            release: metadata.release,
            rateLimit: metadata.rateLimit
        )
    }

    func download(
        _ update: AvailableUpdate,
        eventHandler: @escaping @Sendable (UpdateDownloadEvent) -> Void
    ) async throws -> URL {
        try await artifactDownloader.download(update, eventHandler: eventHandler)
    }
}
