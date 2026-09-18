import Foundation

nonisolated enum WordErrorRate {
    /// Lowercase, strip punctuation, keep letters (including Afrikaans diacritics) and apostrophes.
    static func tokens(_ text: String) -> [String] {
        var scalars: [Character] = []
        scalars.reserveCapacity(text.count)
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "\u{2019}" {
                scalars.append(Character(scalar))
            } else {
                scalars.append(" ")
            }
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    static func levenshtein(_ hypothesis: [String], _ reference: [String]) -> Int {
        if reference.isEmpty { return hypothesis.count }
        if hypothesis.isEmpty { return reference.count }
        var previous = Array(0...reference.count)
        var current = Array(repeating: 0, count: reference.count + 1)
        for (i, hyp) in hypothesis.enumerated() {
            current[0] = i + 1
            for (j, ref) in reference.enumerated() {
                let cost = hyp == ref ? 0 : 1
                current[j + 1] = min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + cost
                )
            }
            swap(&previous, &current)
        }
        return previous[reference.count]
    }

    /// Word error rate in `0...∞`. Empty reference with a non-empty hypothesis is `1`.
    static func ratio(hypothesis: String, reference: String) -> Double {
        let ref = tokens(reference)
        let hyp = tokens(hypothesis)
        if ref.isEmpty { return hyp.isEmpty ? 0 : 1 }
        return Double(levenshtein(hyp, ref)) / Double(ref.count)
    }
}
