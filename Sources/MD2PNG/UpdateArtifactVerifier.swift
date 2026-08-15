import CryptoKit
import Foundation

struct UpdateArtifactVerifier: Sendable {
    func verifyFile(at fileURL: URL, update: AvailableUpdate) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value == update.size else {
            throw UpdateError.fileSizeMismatch
        }
        guard try sha256(for: fileURL) == update.sha256 else {
            throw UpdateError.digestMismatch
        }
    }

    func sha256(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
