import Foundation

/// Whisper re-decodes the whole uncommitted slice every few hundred
/// milliseconds and each pass may render earlier words differently, so
/// feeding hypotheses straight to the screen repaints the entire live line.
/// This folds successive hypotheses into a display string with a locked
/// prefix: a word locks once two consecutive completed decodes agree on it,
/// and locked words only change when two consecutive decodes agree on the
/// same correction.
nonisolated struct PartialStabiliser {
    private(set) var display = ""

    /// Locked prefix, in the rendering it was first shown with.
    private var stableWords: [String] = []
    /// Everything currently on screen: `stableWords` plus a volatile tail.
    private var displayWords: [String] = []
    /// The previous completed decode, for the two-pass agreement rules.
    private var lastFinalWords: [String] = []
    private var hasLastFinal = false

    mutating func reset() {
        display = ""
        stableWords = []
        displayWords = []
        lastFinalWords = []
        hasLastFinal = false
    }

    /// A token-by-token hypothesis from a decode still in flight. These
    /// restart from one word every pass, so they may only grow the tail;
    /// shorter hypotheses leave the screen untouched.
    mutating func updateLive(_ hypothesis: String) -> String {
        let words = Self.words(of: hypothesis)
        guard words.count > stableWords.count, words.count >= displayWords.count else { return display }
        displayWords = stableWords + words[stableWords.count...]
        display = displayWords.joined(separator: " ")
        return display
    }

    /// The completed hypothesis for the current slice. Locks newly agreed
    /// words, adopts corrections the model has repeated, and refreshes the
    /// volatile tail.
    mutating func updateFinal(_ hypothesis: String) -> String {
        let words = Self.words(of: hypothesis)
        defer {
            lastFinalWords = words
            hasLastFinal = true
        }
        if hasLastFinal {
            adoptAgreedCorrection(words)
            extendStablePrefix(words)
        }
        if words.count > stableWords.count {
            displayWords = stableWords + words[stableWords.count...]
        } else if displayWords.count > stableWords.count {
            displayWords = stableWords + displayWords[stableWords.count...]
        } else {
            displayWords = stableWords
        }
        display = displayWords.joined(separator: " ")
        return display
    }

    /// Two consecutive decodes rendering the locked region the same
    /// different way is the model saying it now understands better.
    private mutating func adoptAgreedCorrection(_ words: [String]) {
        let count = stableWords.count
        guard count > 0, words.count >= count, lastFinalWords.count >= count else { return }
        let candidate = Array(words[..<count])
        guard candidate != stableWords, candidate == Array(lastFinalWords[..<count]) else { return }
        stableWords = candidate
    }

    /// Locks newly agreed words with the rendering already on screen — the
    /// previous decode's — so the act of locking never repaints them.
    private mutating func extendStablePrefix(_ words: [String]) {
        let agreed = Self.agreedPrefixLength(words, lastFinalWords)
        guard agreed > stableWords.count else { return }
        stableWords += lastFinalWords[stableWords.count..<agreed]
    }

    private static func agreedPrefixLength(_ a: [String], _ b: [String]) -> Int {
        var length = 0
        while length < a.count, length < b.count, normalized(a[length]) == normalized(b[length]) {
            length += 1
        }
        return length
    }

    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Case and punctuation differences are rendering, not disagreement.
    private static func normalized(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
