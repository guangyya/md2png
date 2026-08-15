import Foundation

final class UpdateArtifactCache: @unchecked Sendable {
    private let directoryOverride: URL?
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        directoryOverride = directory
        self.fileManager = fileManager
    }

    func destination(for update: AvailableUpdate) throws -> URL {
        try cacheDirectory().appendingPathComponent(update.assetName)
    }

    func contains(_ fileURL: URL) -> Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    func discard(_ fileURL: URL) {
        try? fileManager.removeItem(at: fileURL)
    }

    func prepareForDownload() throws -> URL {
        let directory = try cacheDirectory()
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for url in contents where url.lastPathComponent.hasPrefix(".md2png-update-") {
            try? fileManager.removeItem(at: url)
        }
        return directory
    }

    func stageDownloadedFile(_ temporaryURL: URL, in directory: URL) throws -> URL {
        let partialURL = directory.appendingPathComponent(
            ".md2png-update-\(UUID().uuidString).download"
        )
        do {
            try fileManager.moveItem(at: temporaryURL, to: partialURL)
            return partialURL
        } catch {
            throw UpdateError.cacheUnavailable
        }
    }

    func commit(_ partialURL: URL, to destinationURL: URL) throws {
        do {
            try fileManager.moveItem(at: partialURL, to: destinationURL)
        } catch {
            throw UpdateError.cacheUnavailable
        }
    }

    private func cacheDirectory() throws -> URL {
        let directory: URL
        if let directoryOverride {
            directory = directoryOverride
        } else {
            guard let cachesDirectory = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first else {
                throw UpdateError.cacheUnavailable
            }
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "io.github.guangyya.md2png"
            directory = cachesDirectory
                .appendingPathComponent(bundleIdentifier, isDirectory: true)
                .appendingPathComponent("Updates", isDirectory: true)
        }

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            throw UpdateError.cacheUnavailable
        }
    }
}
