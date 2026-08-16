import Foundation

enum UpdateDownloadEvent: Equatable, Sendable {
    case progress(received: Int64, expected: Int64)
    case verifying
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

final class UpdateArtifactDownloader: @unchecked Sendable {
    private let session: URLSession
    private let cache: UpdateArtifactCache
    private let verifier: UpdateArtifactVerifier

    init(
        session: URLSession = UpdateNetworkSession.make(),
        cache: UpdateArtifactCache = UpdateArtifactCache(),
        verifier: UpdateArtifactVerifier = UpdateArtifactVerifier()
    ) {
        self.session = session
        self.cache = cache
        self.verifier = verifier
    }

    func download(
        _ update: AvailableUpdate,
        eventHandler: @escaping @Sendable (UpdateDownloadEvent) -> Void
    ) async throws -> URL {
        let destinationURL = try cache.destination(for: update)

        if cache.contains(destinationURL) {
            do {
                eventHandler(.progress(received: update.size, expected: update.size))
                eventHandler(.verifying)
                try verifier.verifyFile(at: destinationURL, update: update)
                return destinationURL
            } catch {
                cache.discard(destinationURL)
            }
        }

        let cacheDirectory = try cache.prepareForDownload()
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

        let partialURL = try cache.stageDownloadedFile(temporaryURL, in: cacheDirectory)
        defer { cache.discard(partialURL) }

        eventHandler(.progress(received: update.size, expected: update.size))
        eventHandler(.verifying)
        try verifier.verifyFile(at: partialURL, update: update)
        try Task.checkCancellation()
        try cache.commit(partialURL, to: destinationURL)
        return destinationURL
    }
}
