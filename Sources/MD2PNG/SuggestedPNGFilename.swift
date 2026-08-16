import Foundation

enum SuggestedPNGFilename {
    private static let maximumStemLength = 72
    private static let maximumStemUTF8Count = 240

    static func make(
        from markdown: String?,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        if let markdown,
           let candidate = preferredText(from: markdown),
           let stem = sanitizedStem(from: candidate) {
            return "\(stem).png"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "md2png-\(formatter.string(from: now)).png"
    }

    private static func preferredText(from markdown: String) -> String? {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var firstMeaningfulLine: String?
        var fenceCharacter: Character?
        let frontMatterRange = yamlFrontMatterRange(in: lines)

        for index in lines.indices {
            if frontMatterRange?.contains(index) == true { continue }
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if let marker = fenceMarker(in: trimmed) {
                if fenceCharacter == nil {
                    fenceCharacter = marker
                } else if fenceCharacter == marker {
                    fenceCharacter = nil
                }
                continue
            }
            guard fenceCharacter == nil else { continue }

            if let heading = atxHeading(in: trimmed) {
                return heading
            }
            if index + 1 < lines.count,
               isSetextUnderline(lines[index + 1]),
               !trimmed.isEmpty {
                return trimmed
            }
            if firstMeaningfulLine == nil,
               isMeaningfulFallback(trimmed) {
                firstMeaningfulLine = trimmed
            }
        }

        return firstMeaningfulLine
    }

    private static func yamlFrontMatterRange(in lines: [String]) -> ClosedRange<Int>? {
        guard let start = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), lines[start].trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return nil
        }
        guard let end = lines.indices.dropFirst(start + 1).first(where: {
            let delimiter = lines[$0].trimmingCharacters(in: .whitespacesAndNewlines)
            return delimiter == "---" || delimiter == "..."
        }) else {
            return nil
        }
        return start...end
    }

    private static func fenceMarker(in line: String) -> Character? {
        guard let character = line.first, character == "`" || character == "~" else {
            return nil
        }
        return line.prefix(while: { $0 == character }).count >= 3 ? character : nil
    }

    private static func atxHeading(in line: String) -> String? {
        let hashCount = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashCount) else { return nil }
        let contentStart = line.index(line.startIndex, offsetBy: hashCount)
        guard contentStart == line.endIndex || line[contentStart].isWhitespace else { return nil }
        var content = String(line[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        content = content.replacingOccurrences(
            of: #"\s+#+\s*$"#,
            with: "",
            options: .regularExpression
        )
        return content.isEmpty ? nil : content
    }

    private static func isSetextUnderline(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, let marker = trimmed.first,
              marker == "=" || marker == "-" else { return false }
        return trimmed.allSatisfy { $0 == marker }
    }

    private static func isMeaningfulFallback(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        let compact = line.filter { !$0.isWhitespace }
        if compact.count >= 3,
           compact.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) {
            return false
        }
        if line.hasPrefix("<!--") || line.range(
            of: #"^\[[^\]]+\]:\s*\S+"#,
            options: .regularExpression
        ) != nil {
            return false
        }
        return true
    }

    private static func sanitizedStem(from source: String) -> String? {
        var value = source
        let replacements: [(String, String)] = [
            (#"!\[([^\]]*)\]\([^)]*\)"#, "$1"),
            (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
            (#"\[([^\]]+)\]\[[^\]]*\]"#, "$1"),
            (#"<https?://[^>]+>"#, " "),
            (#"<[^>]+>"#, " "),
            (#"^\s*(?:>\s*)+"#, ""),
            (#"^\s*(?:[-+*]|\d+[.)])\s+"#, ""),
            (#"[*_~`]"#, "")
        ]
        for (pattern, replacement) in replacements {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        value = value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(
                of: #"[/\\:*?\"<>|]"#,
                with: " ",
                options: .regularExpression
            )
        value = value.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: #"[.\s-]+$"#,
            with: "",
            options: .regularExpression
        )
        if value.lowercased().hasSuffix(".png") {
            value.removeLast(4)
        }
        var limitedStem = ""
        for character in value {
            let candidate = limitedStem + String(character)
            guard candidate.count <= maximumStemLength,
                  candidate.utf8.count <= maximumStemUTF8Count else { break }
            limitedStem = candidate
        }
        let stem = limitedStem.replacingOccurrences(
            of: #"[.\s-]+$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty, stem != ".", stem != ".." else { return nil }
        return stem
    }
}
