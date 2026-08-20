import Foundation
@testable import MD2PNG

enum UpdateTestFixtures {
    static let repository = GitHubRepository(
        projectURL: URL(string: "https://github.com/guangyya/md2png")!
    )!

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
