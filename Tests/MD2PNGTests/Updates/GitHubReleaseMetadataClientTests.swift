import Foundation
import XCTest
@testable import MD2PNG

final class GitHubReleaseMetadataClientTests: XCTestCase {
    private let repository = UpdateTestFixtures.repository

    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testFetchMapsGitHubPayloadToReleaseDomainWithExpectedHeaders() async throws {
        let capturedRequest = LockedBox<URLRequest?>(nil)
        let responseData = Data(UpdateTestFixtures.releaseJSON(version: "0.2.0").utf8)
        URLProtocolStub.handler = { request in
            capturedRequest.set(request)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/json",
                        "X-RateLimit-Remaining": "42",
                        "X-RateLimit-Reset": "2000"
                    ]
                )!,
                responseData
            )
        }
        let client = GitHubReleaseMetadataClient(session: UpdateTestFixtures.stubbedSession())

        let response = try await client.fetchLatestRelease(
            repository: repository,
            userAgentVersion: "0.1.0"
        )

        XCTAssertEqual(response.release, UpdateTestFixtures.release(version: "0.2.0"))
        let request = try XCTUnwrap(capturedRequest.value)
        XCTAssertEqual(request.url, repository.latestReleaseAPIURL)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "md2png-update-check/0.1.0")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(response.rateLimit.remaining, 42)
        XCTAssertEqual(response.rateLimit.resetAt, Date(timeIntervalSince1970: 2_000))
    }

    func testFetchReportsHTTPAndMalformedJSONFailures() async throws {
        URLProtocolStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }
        let client = GitHubReleaseMetadataClient(session: UpdateTestFixtures.stubbedSession())
        let currentDate = Date(timeIntervalSince1970: 1_000)
        do {
            _ = try await client.fetchLatestRelease(
                repository: repository,
                userAgentVersion: "0.1.0",
                now: currentDate
            )
            XCTFail("Expected HTTP failure")
        } catch {
            XCTAssertEqual(
                error as? UpdateError,
                .rateLimited(retryAt: currentDate.addingTimeInterval(60))
            )
        }

        URLProtocolStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data("not-json".utf8)
            )
        }
        do {
            _ = try await client.fetchLatestRelease(
                repository: repository,
                userAgentVersion: "0.1.0"
            )
            XCTFail("Expected malformed JSON failure")
        } catch {
            XCTAssertEqual(error as? UpdateError, .invalidServerResponse)
        }
    }

    func testFetchUsesRetryAfterAndRateLimitResetHeaders() async throws {
        let currentDate = Date(timeIntervalSince1970: 1_000)
        URLProtocolStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "120"]
                )!,
                Data()
            )
        }
        let client = GitHubReleaseMetadataClient(session: UpdateTestFixtures.stubbedSession())
        do {
            _ = try await client.fetchLatestRelease(
                repository: repository,
                userAgentVersion: "0.1.0",
                now: currentDate
            )
            XCTFail("Expected rate limit")
        } catch {
            XCTAssertEqual(
                error as? UpdateError,
                .rateLimited(retryAt: currentDate.addingTimeInterval(120))
            )
        }

        URLProtocolStub.handler = { request in
            (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 429,
                    httpVersion: nil,
                    headerFields: [
                        "X-RateLimit-Remaining": "0",
                        "X-RateLimit-Reset": "1300"
                    ]
                )!,
                Data()
            )
        }
        do {
            _ = try await client.fetchLatestRelease(
                repository: repository,
                userAgentVersion: "0.1.0",
                now: currentDate
            )
            XCTFail("Expected rate limit")
        } catch {
            XCTAssertEqual(
                error as? UpdateError,
                .rateLimited(retryAt: Date(timeIntervalSince1970: 1_300))
            )
        }
    }
}
