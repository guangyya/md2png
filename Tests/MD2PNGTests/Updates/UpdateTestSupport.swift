import Foundation
@testable import MD2PNG

enum UpdateTestFixtures {
    static let repository = GitHubRepository(
        projectURL: URL(string: "https://github.com/guangyya/md2png")!
    )!

    static let sha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    static func release(
        version: String,
        draft: Bool = false,
        prerelease: Bool = false
    ) -> UpdateRelease {
        let normalizedVersion = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let tag = version.hasPrefix("v") ? version : "v\(version)"
        let assetName = "md2png-\(normalizedVersion)-macOS-arm64-developer-id.dmg"
        return UpdateRelease(
            tagName: tag,
            draft: draft,
            prerelease: prerelease,
            assets: [UpdateReleaseAsset(
                name: assetName,
                contentType: UpdateReleaseResolver.diskImageContentType,
                size: 3,
                digest: "sha256:\(sha256)",
                downloadURL: URL(
                    string: "https://github.com/guangyya/md2png/releases/download/\(tag)/\(assetName)"
                )!
            )]
        )
    }

    static func availableUpdate(version: String = "0.2.0") -> AvailableUpdate {
        let release = release(version: version)
        let asset = release.assets[0]
        return AvailableUpdate(
            version: SemanticVersion(version)!,
            tagName: release.tagName,
            assetName: asset.name,
            downloadURL: asset.downloadURL,
            size: asset.size,
            sha256: sha256
        )
    }

    static func seamlessUpdate(
        installedVersion: String = "0.7.0",
        version: String = "0.8.0",
        build: String = "8"
    ) -> SeamlessUpdate {
        SeamlessUpdate(
            installedVersion: installedVersion,
            displayVersion: version,
            buildVersion: build,
            publishedAt: Date(timeIntervalSince1970: 1_787_000_000),
            contentLength: 4_200_000,
            releaseNotes: [SeamlessUpdateReleaseNotes(
                version: version,
                publishedAt: Date(timeIntervalSince1970: 1_787_000_000),
                text: "Added\n- Seamless updates."
            )],
            historyIsTruncated: false,
            fullReleaseNotesURL: URL(
                string: "https://github.com/guangyya/md2png/releases"
            )
        )
    }

    static func releaseJSON(
        version: String,
        draft: Bool = false,
        prerelease: Bool = false
    ) -> String {
        let normalizedVersion = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let tag = version.hasPrefix("v") ? version : "v\(version)"
        let assetName = "md2png-\(normalizedVersion)-macOS-arm64-developer-id.dmg"
        return """
        {
          "tag_name": "\(tag)",
          "draft": \(draft),
          "prerelease": \(prerelease),
          "assets": [{
            "name": "\(assetName)",
            "content_type": "application/x-apple-diskimage",
            "size": 3,
            "digest": "sha256:\(sha256)",
            "browser_download_url": "https://github.com/guangyya/md2png/releases/download/\(tag)/\(assetName)"
          }]
        }
        """
    }

    static func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    static func makeDefaults() -> UserDefaults {
        let suiteName = "MD2PNGUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(suiteName, forKey: "TestSuiteName")
        return defaults
    }

    static func removeDefaults(_ defaults: UserDefaults) {
        guard let suiteName = defaults.string(forKey: "TestSuiteName") else { return }
        defaults.removePersistentDomain(forName: suiteName)
    }
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }
}

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
