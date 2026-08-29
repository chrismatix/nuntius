import Foundation

/// Merges the manual vocabulary setting with an optional folder of .txt term lists.
enum VocabularyStore {
    /// Directory terms come first so the manual list sits at the prompt tail,
    /// which is the part whisper keeps when the prompt overruns its token cap.
    static func currentPrompt() -> String {
        let defaults = UserDefaults.standard
        let manual = defaults.string(forKey: "vocabularyPrompt") ?? ""
        let directory = defaults.string(forKey: "vocabularyDirectory") ?? ""

        var seenTerms = Set<String>()
        var terms: [String] = []
        for line in directoryLines(in: directory) + manual.components(separatedBy: .newlines) {
            let term = line.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, seenTerms.insert(term.lowercased()).inserted else { continue }
            terms.append(term)
        }
        return terms.joined(separator: "\n")
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
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func directoryLines(in path: String) -> [String] {
        dictionaryFiles(in: path).flatMap { fileURL -> [String] in
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
            return content.components(separatedBy: .newlines)
        }
    }
}
