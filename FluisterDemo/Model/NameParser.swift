import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Pulls a display name out of an introduction. Heuristics first; on-device
/// Foundation Models when the OS has Apple Intelligence, for messy replies.
nonisolated enum NameParser: Sendable {
    static let maxNameWords = 3

    static func displayName(from utterance: String) -> String? {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let tagged = matchIntroduction(trimmed) { return tagged }
        return standaloneName(trimmed)
    }

    static func resolvedName(from utterance: String) async -> String? {
        if let fast = displayName(from: utterance) { return fast }
        return await foundationName(from: utterance)
    }

    private static func matchIntroduction(_ text: String) -> String? {
        let lower = fold(text)
        let patterns = [
            "my name is ",
            "my naam is ",
            "i am ",
            "i'm ",
            "im ",
            "ek is ",
            "dit is ",
            "dis ",
            "it's ",
            "its ",
            "this is ",
            "i is ",
        ]
        for prefix in patterns {
            guard let range = lower.range(of: prefix) else { continue }
            let rest = String(lower[range.upperBound...])
            if let name = firstNamePhrase(rest) { return name }
        }
        return nil
    }

    private static func standaloneName(_ text: String) -> String? {
        let tokens = fold(text)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !fillers.contains($0) }
        guard (1...maxNameWords).contains(tokens.count) else { return nil }
        guard tokens.allSatisfy({ !blocked.contains($0) && isPlausibleNameToken($0) }) else { return nil }
        return titled(tokens.joined(separator: " "))
    }

    private static func firstNamePhrase(_ rest: String) -> String? {
        var tokens = rest
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "." || $0 == "!" || $0 == "?" })
            .map(String.init)
        while let first = tokens.first, fillers.contains(first) {
            tokens.removeFirst()
        }
        var taken: [String] = []
        for token in tokens {
            if blocked.contains(token) { break }
            guard isPlausibleNameToken(token) else { break }
            taken.append(token)
            if taken.count == maxNameWords { break }
        }
        guard !taken.isEmpty else { return nil }
        return titled(taken.joined(separator: " "))
    }

    private static func isPlausibleNameToken(_ token: String) -> Bool {
        guard token.count >= 2, token.count <= 24 else { return false }
        return token.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) || $0 == "-" || $0 == "'" }
    }

    private static func titled(_ name: String) -> String {
        name.split(separator: " ").map { part in
            guard let first = part.first else { return String(part) }
            return String(first).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }

    private static func fold(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
    }

    private static let fillers: Set<String> = [
        "um", "uh", "ah", "er", "n", "nè", "ne", "ja", "nee", "hi", "hey", "hello",
        "hallo", "ok", "okay", "wel", "well", "so",
    ]

    private static let blocked: Set<String> = [
        "tired", "fine", "here", "good", "back", "sorry", "the", "a", "an", "and",
        "to", "for", "of", "in", "on", "at", "it", "is", "am", "ek", "my", "naam",
        "name", "not", "yes", "no", "wat", "what", "who", "hoe", "how", "going",
        "doing", "just", "like", "you", "jou", "your", "ons", "we", "they", "hulle",
        "speaker", "fluister",
    ]

    private static func foundationName(from utterance: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            return await askFoundationModel(utterance)
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    @available(iOS 26, macOS 26, *)
    private static func askFoundationModel(_ utterance: String) async -> String? {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return nil }
        let session = LanguageModelSession()
        let prompt = """
        Extract the person's given name if they are introducing themselves. \
        Reply with the name only, or NONE if there is no name.
        Transcript: \(utterance)
        """
        do {
            let response = try await session.respond(to: prompt)
            let raw = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { return nil }
            if raw.compare("NONE", options: .caseInsensitive) == .orderedSame { return nil }
            return displayName(from: raw) ?? titled(fold(raw))
        } catch {
            return nil
        }
    }
    #endif
}
