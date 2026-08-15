import Foundation

struct CachedUpdateReleaseRecord: Equatable {
    let repositoryOwner: String
    let repositoryName: String
    let checkedAt: Date
    let release: UpdateRelease

    func matches(_ repository: GitHubRepository) -> Bool {
        repositoryOwner == repository.owner && repositoryName == repository.name
    }
}

extension CachedUpdateReleaseRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case repositoryOwner
        case repositoryName
        case checkedAt
        case release
    }

    private struct LegacyRelease: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [LegacyAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft
            case prerelease
            case assets
        }

        var updateRelease: UpdateRelease {
            UpdateRelease(
                tagName: tagName,
                draft: draft,
                prerelease: prerelease,
                assets: assets.map(\.updateAsset)
            )
        }
    }

    private struct LegacyAsset: Decodable {
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

        var updateAsset: UpdateReleaseAsset {
            UpdateReleaseAsset(
                name: name,
                contentType: contentType,
                size: size,
                digest: digest,
                downloadURL: browserDownloadURL
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repositoryOwner = try container.decode(String.self, forKey: .repositoryOwner)
        repositoryName = try container.decode(String.self, forKey: .repositoryName)
        checkedAt = try container.decode(Date.self, forKey: .checkedAt)
        if let release = try? container.decode(UpdateRelease.self, forKey: .release) {
            self.release = release
        } else {
            release = try container.decode(LegacyRelease.self, forKey: .release).updateRelease
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(repositoryOwner, forKey: .repositoryOwner)
        try container.encode(repositoryName, forKey: .repositoryName)
        try container.encode(checkedAt, forKey: .checkedAt)
        try container.encode(release, forKey: .release)
    }
}

final class UpdateCheckPolicy {
    private enum DefaultsKey {
        static let cachedRelease = "Update.cachedRelease.v1"
        static let lastAttemptAt = "Update.lastAttemptAt.v1"
        static let serverRetryAt = "Update.serverRetryAt.v1"
    }

    private let defaults: UserDefaults
    private let automaticCheckInterval: TimeInterval
    private let manualCheckCooldown: TimeInterval

    init(
        defaults: UserDefaults,
        automaticCheckInterval: TimeInterval,
        manualCheckCooldown: TimeInterval
    ) {
        self.defaults = defaults
        self.automaticCheckInterval = automaticCheckInterval
        self.manualCheckCooldown = manualCheckCooldown
    }

    func cachedRelease(for repository: GitHubRepository) -> CachedUpdateReleaseRecord? {
        guard let data = defaults.data(forKey: DefaultsKey.cachedRelease),
              let record = try? PropertyListDecoder().decode(
                CachedUpdateReleaseRecord.self,
                from: data
              ),
              record.matches(repository) else {
            return nil
        }
        return record
    }

    func cache(
        release: UpdateRelease,
        repository: GitHubRepository,
        checkedAt: Date
    ) {
        let record = CachedUpdateReleaseRecord(
            repositoryOwner: repository.owner,
            repositoryName: repository.name,
            checkedAt: checkedAt,
            release: release
        )
        if let data = try? PropertyListEncoder().encode(record) {
            defaults.set(data, forKey: DefaultsKey.cachedRelease)
        }
    }

    func isFresh(_ record: CachedUpdateReleaseRecord, at date: Date) -> Bool {
        date.timeIntervalSince(record.checkedAt) < automaticCheckInterval
    }

    func recordAttempt(at date: Date) {
        defaults.set(date, forKey: DefaultsKey.lastAttemptAt)
    }

    func recordServerRetry(at date: Date) {
        defaults.set(date, forKey: DefaultsKey.serverRetryAt)
    }

    func applySuccessfulRateLimit(_ rateLimit: GitHubRateLimitInfo, at date: Date) {
        if rateLimit.remaining == 0, let resetAt = rateLimit.resetAt, resetAt > date {
            defaults.set(resetAt, forKey: DefaultsKey.serverRetryAt)
        } else {
            defaults.removeObject(forKey: DefaultsKey.serverRetryAt)
        }
    }

    func canMakeRequest(at date: Date) -> Bool {
        guard let nextAllowed = nextAllowedRequestDate(at: date) else { return true }
        return nextAllowed <= date
    }

    func localRetryDate(after date: Date) -> Date {
        date.addingTimeInterval(manualCheckCooldown)
    }

    func nextAllowedRequestDate(at date: Date) -> Date? {
        var candidates: [Date] = []
        if let lastAttemptAt = defaults.object(forKey: DefaultsKey.lastAttemptAt) as? Date {
            candidates.append(lastAttemptAt.addingTimeInterval(manualCheckCooldown))
        }
        if let serverRetryAt = defaults.object(forKey: DefaultsKey.serverRetryAt) as? Date {
            if serverRetryAt > date {
                candidates.append(serverRetryAt)
            } else {
                defaults.removeObject(forKey: DefaultsKey.serverRetryAt)
            }
        }
        return candidates.max()
    }
}
