import Foundation

/// Merges the manual vocabulary setting with an optional folder of .txt term lists.
enum VocabularyStore {
    /// Whisper keeps the prompt tail on overrun, so the merge builds toward the
    /// end: files in reverse name order (the alphabetically-first, most curated
    /// list lands last), the manual terms after everything, and duplicates
    /// resolved to their latest position.
    static func currentPrompt() -> String {
        let defaults = UserDefaults.standard
        let manual = defaults.string(forKey: "vocabularyPrompt") ?? ""
        let directory = defaults.string(forKey: "vocabularyDirectory") ?? ""

        let lines = directoryLines(in: directory) + manual.components(separatedBy: .newlines)
        var seenTerms = Set<String>()
        var terms: [String] = []
        for line in lines.reversed() {
            let term = line.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, seenTerms.insert(term.lowercased()).inserted else { continue }
            terms.append(term)
        }
        // Comma-joined: whisper degenerates to "..." on a newline-separated prompt.
        return terms.reversed().joined(separator: ", ")
    }

    /// The .txt files that would be read, in the order they are merged.
    static func dictionaryFiles(in path: String) -> [URL] {
        guard !path.isEmpty else { return [] }
        let directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "txt" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private static func directoryLines(in path: String) -> [String] {
        dictionaryFiles(in: path).flatMap { fileURL -> [String] in
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
            return content.components(separatedBy: .newlines)
        }
    }
}
