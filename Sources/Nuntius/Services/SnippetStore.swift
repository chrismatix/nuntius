import AppKit
import Foundation
import os

struct Snippet: Identifiable, Codable, Hashable {
    let id: UUID
    var trigger: String
    var expansionRTF: Data
    var requiresIsolation: Bool

    init(id: UUID = UUID(), trigger: String, expansionRTF: Data, requiresIsolation: Bool) {
        self.id = id
        self.trigger = trigger
        self.expansionRTF = expansionRTF
        self.requiresIsolation = requiresIsolation
    }

    func expansionAttributedString() -> NSAttributedString {
        guard !expansionRTF.isEmpty else {
            return NSAttributedString(string: "")
        }

        if let attributed = try? NSAttributedString(
            data: expansionRTF,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) {
            return attributed
        }

        if let fallback = String(data: expansionRTF, encoding: .utf8) {
            return NSAttributedString(string: fallback)
        }

        return NSAttributedString(string: "")
    }

    var expansionPlainText: String {
        expansionAttributedString().string
    }
}

@MainActor
@Observable
final class SnippetStore {
    static let shared = SnippetStore()

    private let logger = Logger(subsystem: "com.chrismatix.nuntius", category: "SnippetStore")
    private let storageKey = "snippetLibrary"

    private(set) var snippets: [Snippet] = []

    private init() {
        load()
    }

    func add(_ snippet: Snippet) {
        snippets.append(snippet)
        save()
    }

    func update(_ snippet: Snippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[index] = snippet
        save()
    }

    func delete(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
        save()
    }

    func expandTextIfNeeded(_ text: String) -> OutputContent? {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedText.isEmpty else { return nil }

        let usableSnippets = snippets.filter { !$0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !usableSnippets.isEmpty else { return nil }

        if let isolated = matchIsolationSnippet(in: cleanedText, snippets: usableSnippets) {
            let attributed = isolated.expansionAttributedString()
            let plain = attributed.string
            return OutputContent(plainText: plain, richText: attributed)
        }

        let matches = findInlineMatches(in: cleanedText, snippets: usableSnippets)
        guard !matches.isEmpty else { return nil }

        let output = buildAttributedOutput(from: cleanedText, matches: matches)
        return OutputContent(plainText: output.string, richText: output)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            snippets = []
            return
        }

        do {
            snippets = try JSONDecoder().decode([Snippet].self, from: data)
        } catch {
            logger.error("Failed to decode snippets: \(error.localizedDescription)")
            snippets = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(snippets)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logger.error("Failed to encode snippets: \(error.localizedDescription)")
        }
    }

    private func matchIsolationSnippet(in text: String, snippets: [Snippet]) -> Snippet? {
        let normalizedText = normalizeForIsolation(text)

        for snippet in snippets where snippet.requiresIsolation {
            if normalizeForIsolation(snippet.trigger) == normalizedText {
                return snippet
            }
        }

        return nil
    }

    private func normalizeForIsolation(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
    }

    private struct SnippetMatch {
        let range: NSRange
        let snippet: Snippet
    }

    private func findInlineMatches(in text: String, snippets: [Snippet]) -> [SnippetMatch] {
        let candidates = snippets.filter { !$0.requiresIsolation }
        guard !candidates.isEmpty else { return [] }

        var matches: [SnippetMatch] = []

        for snippet in candidates {
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty else { continue }

            let escaped = NSRegularExpression.escapedPattern(for: trigger)
            let pattern = "(?<![\\p{L}\\p{N}_])" + escaped + "(?![\\p{L}\\p{N}_])"

            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match else { return }
                matches.append(SnippetMatch(range: match.range, snippet: snippet))
            }
        }

        if matches.isEmpty { return [] }

        return matches.sorted {
            if $0.range.location != $1.range.location {
                return $0.range.location < $1.range.location
            }
            return $0.range.length > $1.range.length
        }
    }

    private func buildAttributedOutput(from text: String, matches: [SnippetMatch]) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let nsText = text as NSString
        var cursor = 0

        for match in matches {
            guard match.range.location >= cursor else { continue }
            let prefixLength = match.range.location - cursor
            if prefixLength > 0 {
                let prefixRange = NSRange(location: cursor, length: prefixLength)
                output.append(NSAttributedString(string: nsText.substring(with: prefixRange)))
            }

            let snippetAttributed = match.snippet.expansionAttributedString()
            output.append(snippetAttributed)

            cursor = match.range.location + match.range.length
        }

        if cursor < nsText.length {
            let tailRange = NSRange(location: cursor, length: nsText.length - cursor)
            output.append(NSAttributedString(string: nsText.substring(with: tailRange)))
        }

        return output
    }
}
