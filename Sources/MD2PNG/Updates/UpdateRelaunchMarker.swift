import Foundation

enum UpdateRelaunchResult: Equatable {
    case updated(version: String)
    case notUpdated(expectedVersion: String, runningVersion: String)
}

@MainActor
struct UpdateRelaunchMarker {
    static let expectedVersionKey = "Update.pendingRelaunchVersion.v1"
    static let createdAtKey = "Update.pendingRelaunchCreatedAt.v1"
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func mark(expectedVersion: String, at date: Date = Date()) {
        defaults.set(expectedVersion, forKey: Self.expectedVersionKey)
        defaults.set(date, forKey: Self.createdAtKey)
    }

    func clearPendingResult() {
        clear()
    }

    func reconcile(
        runningVersion: String,
        at date: Date = Date()
    ) -> UpdateRelaunchResult? {
        guard let expectedVersion = defaults.string(
            forKey: Self.expectedVersionKey
        ) else {
            clear()
            return nil
        }
        let createdAt = defaults.object(forKey: Self.createdAtKey) as? Date
        clear()

        guard let createdAt,
              date.timeIntervalSince(createdAt) >= 0,
              date.timeIntervalSince(createdAt) <= Self.maximumAge else {
            return nil
        }
        if runningVersion == expectedVersion {
            return .updated(version: runningVersion)
        }
        return .notUpdated(
            expectedVersion: expectedVersion,
            runningVersion: runningVersion
        )
    }

    private func clear() {
        defaults.removeObject(forKey: Self.expectedVersionKey)
        defaults.removeObject(forKey: Self.createdAtKey)
    }
}
