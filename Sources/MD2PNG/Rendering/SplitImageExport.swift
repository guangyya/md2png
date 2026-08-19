import AppKit
import Foundation

enum SplitImageExportPolicy {
    static let maximumSliceHeight = 4_000
}

enum SplitImageExportNaming {
    private static let maximumFileNameUTF8Count = 240

    static func suggestedDirectoryName(
        from markdown: String,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let suggestedPNG = SuggestedPNGFilename.make(
            from: markdown,
            now: now,
            timeZone: timeZone
        )
        let stem = (suggestedPNG as NSString).deletingPathExtension
        return "\(stem)-split"
    }

    static func fileNames(
        directoryName: String,
        count: Int
    ) -> [String] {
        guard count > 0 else { return [] }
        let digits = max(2, String(count).count)
        let suffixLength = "-\(String(repeating: "0", count: digits)).png".utf8.count
        let sourceStem = directoryName.isEmpty ? "md2png-split" : directoryName
        let stem = limitedPrefix(
            sourceStem,
            maximumUTF8Count: maximumFileNameUTF8Count - suffixLength
        )
        return (1 ... count).map { index in
            "\(stem)-\(String(format: "%0\(digits)d", index)).png"
        }
    }

    private static func limitedPrefix(
        _ value: String,
        maximumUTF8Count: Int
    ) -> String {
        var result = ""
        for character in value {
            let candidate = result + String(character)
            guard candidate.utf8.count <= maximumUTF8Count else { break }
            result = candidate
        }
        return result.isEmpty ? "md2png" : result
    }
}

enum SplitImageExportWriter {
    private struct PreparedFile: Sendable {
        let name: String
        let data: Data
    }

    @MainActor
    static func write(
        _ result: SplitRenderResult,
        to destinationDirectoryURL: URL,
        cornerStyle: RenderCornerStyle = .square
    ) async throws {
        let directoryName = destinationDirectoryURL.lastPathComponent
        let names = SplitImageExportNaming.fileNames(
            directoryName: directoryName,
            count: result.parts.count
        )
        let files = try zip(names, result.parts).map { name, part in
            let outputImage = try RenderedImageStyler.apply(
                cornerStyle,
                to: part.image
            )
            return PreparedFile(
                name: name,
                data: try RenderedImageExport.pngData(for: outputImage)
            )
        }
        do {
            try await Task.detached(priority: .utility) {
                try writePreparedFiles(
                    files,
                    to: destinationDirectoryURL
                )
            }.value
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.splitExportWriteFailed
        }
    }

    private static func writePreparedFiles(
        _ files: [PreparedFile],
        to destinationDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !files.isEmpty,
              !destinationDirectoryURL.lastPathComponent.isEmpty,
              !fileManager.fileExists(atPath: destinationDirectoryURL.path) else {
            throw AppError.splitExportWriteFailed
        }
        let parentURL = destinationDirectoryURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
            ".md2png-split-\(UUID().uuidString)",
            isDirectory: true
        )
        var createdStagingDirectory = false
        do {
            try fileManager.createDirectory(
                at: stagingURL,
                withIntermediateDirectories: false
            )
            createdStagingDirectory = true
            for file in files {
                try file.data.write(
                    to: stagingURL.appendingPathComponent(file.name),
                    options: .atomic
                )
            }
            try fileManager.moveItem(
                at: stagingURL,
                to: destinationDirectoryURL
            )
        } catch {
            if createdStagingDirectory {
                try? fileManager.removeItem(at: stagingURL)
            }
            throw AppError.splitExportWriteFailed
        }
    }
}
