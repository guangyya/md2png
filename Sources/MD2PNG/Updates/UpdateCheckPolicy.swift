import Foundation

final class UpdateCheckPolicy {
    private enum DefaultsKey {
        static let lastAttemptAt = "Update.lastAttemptAt.v1"
    }

    private let defaults: UserDefaults
    private let manualCheckCooldown: TimeInterval

    init(
        defaults: UserDefaults,
        manualCheckCooldown: TimeInterval
    ) {
        self.defaults = defaults
        self.manualCheckCooldown = manualCheckCooldown
    }

    func recordAttempt(at date: Date) {
        defaults.set(date, forKey: DefaultsKey.lastAttemptAt)
    }

    func canMakeRequest(at date: Date) -> Bool {
        guard let nextAllowed = nextAllowedRequestDate() else { return true }
        return nextAllowed <= date
    }

    func localRetryDate(after date: Date) -> Date {
        date.addingTimeInterval(manualCheckCooldown)
    }

    func nextAllowedRequestDate() -> Date? {
        guard let lastAttemptAt = defaults.object(
            forKey: DefaultsKey.lastAttemptAt
        ) as? Date else {
            return nil
        }
        return lastAttemptAt.addingTimeInterval(manualCheckCooldown)
    }
}
