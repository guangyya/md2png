import Foundation

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAssetPayload]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }

    var release: UpdateRelease {
        UpdateRelease(
            tagName: tagName,
            draft: draft,
            prerelease: prerelease,
            assets: assets.map(\.releaseAsset)
        )
    }
}

private struct GitHubReleaseAssetPayload: Decodable {
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

    var releaseAsset: UpdateReleaseAsset {
        UpdateReleaseAsset(
            name: name,
            contentType: contentType,
            size: size,
            digest: digest,
            downloadURL: browserDownloadURL
        )
    }
}

struct GitHubRateLimitInfo: Equatable, Sendable {
    let remaining: Int?
    let resetAt: Date?
}

struct GitHubReleaseMetadataResponse: Equatable, Sendable {
    let release: UpdateRelease
    let rateLimit: GitHubRateLimitInfo
}

final class GitHubReleaseMetadataClient: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = UpdateNetworkSession.make()) {
        self.session = session
    }

    func fetchLatestRelease(
        repository: GitHubRepository,
        userAgentVersion: String,
        now: Date = Date()
    ) async throws -> GitHubReleaseMetadataResponse {
        var request = URLRequest(url: repository.latestReleaseAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(
            "md2png-update-check/\(userAgentVersion)",
            forHTTPHeaderField: "User-Agent"
        )

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

        let payload: GitHubReleasePayload
        do {
            payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        } catch {
            throw UpdateError.invalidServerResponse
        }
        return GitHubReleaseMetadataResponse(
            release: payload.release,
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
}
