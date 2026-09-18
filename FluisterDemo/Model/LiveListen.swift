import Foundation
@preconcurrency import WhisperKit

/// Live-microphone policy. WhisperKit's `AudioStreamTranscriber` is a poor fit for
/// this demo: it re-encodes the whole session, clips the last second of every window
/// (`windowClipTime` defaults to 1s), waits for two extra segments before confirming,
/// and writes "Waiting for speech..." into the transcript.
nonisolated enum LiveListen: Sendable {
    static let waitingPlaceholder = "Waiting for speech..."
    /// How much new audio to collect before another decode. The model transcribes a
    /// 30s clip in ~2s; a 0.3s slice is effectively immediate.
    static let minNewSeconds: Double = 0.3
    static let overlapSeconds: Double = 0.2
    /// Commit the live line after this much trailing silence. Whisper degrades badly
    /// on short context-free utterances, so a pause at a sentence or poem line break
    /// must not split the utterance.
    static let silenceCommitSeconds: Double = 1.2
    /// Utterances with less voiced audio than this are decoder noise ("tjie"-style
    /// orphan fragments), not speech worth a caption.
    static let minVoicedSeconds: Double = 0.7
    static let voiceEnergy: Float = 0.15
    static let pollNanoseconds: UInt64 = 50_000_000

    static var minNewSamples: Int { Int(minNewSeconds * Double(WhisperKit.sampleRate)) }
    static var overlapSamples: Int { Int(overlapSeconds * Double(WhisperKit.sampleRate)) }
    /// WhisperKit records relative energy in 100 ms frames.
    static var trailingSilenceFrames: Int { max(1, Int((silenceCommitSeconds / 0.1).rounded())) }
    static var minVoicedFrames: Int { max(1, Int((minVoicedSeconds / 0.1).rounded())) }
    static var energyFrameSamples: Int { WhisperKit.sampleRate / 10 }

    /// Options for streaming partial decodes: greedy only, so a bad slice never
    /// stalls the live line behind fallback retries.
    ///
    /// Never set `promptTokens` here: the Fluister fine-tune was not trained with
    /// `<|startofprev|>` previous-text conditioning and decodes prompted audio to
    /// an empty string (verified by `livePipelineWERTracksWholeClipDecode` — a
    /// prompted variant scored 0.41 mean WER against 0.06 unprompted).
    static func decodingOptions(language: String) -> DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: language,
            temperature: 0,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: false,
            skipSpecialTokens: true,
            wordTimestamps: false,
            windowClipTime: 0,
            concurrentWorkerCount: 1,
            chunkingStrategy: ChunkingStrategy.none
        )
    }

    /// Options for the one decode whose text is committed as a caption: latency
    /// matters less than accuracy there, so temperature fallback is back on.
    static func finalDecodingOptions(language: String) -> DecodingOptions {
        var options = decodingOptions(language: language)
        options.temperatureFallbackCount = 3
        return options
    }

    static func visibleText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.compare(waitingPlaceholder, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return ""
        }
        return trimmed
    }

    static func isVoice(in energy: ArraySlice<Float>) -> Bool {
        energy.contains { $0 > voiceEnergy }
    }

    static func voicedFrameCount(in energy: ArraySlice<Float>) -> Int {
        energy.count(where: { $0 > voiceEnergy })
    }
}

/// Decides where one utterance ends and the next begins, from the same sample
/// counts and 100 ms relative-energy frames the recorder produces. Kept as a pure
/// state machine so the live loop and the ASR eval harness segment identically.
nonisolated struct LiveListenSegmenter {
    private(set) var committedSamples = 0
    private var heardVoice = false

    struct Commit: Equatable {
        let utterance: Range<Int>
        /// False when the utterance had too little voiced audio to be speech;
        /// callers should discard it instead of decoding.
        let voiced: Bool
    }

    /// Feed the latest recording state; returns the utterance to finalise once
    /// speech has been followed by `silenceCommitSeconds` of quiet.
    mutating func step(sampleCount: Int, energy: [Float]) -> Commit? {
        let trailing = energy.suffix(LiveListen.trailingSilenceFrames)
        if LiveListen.isVoice(in: trailing) {
            heardVoice = true
            return nil
        }
        guard heardVoice, trailing.count >= LiveListen.trailingSilenceFrames else { return nil }
        let start = min(committedSamples, sampleCount)
        let frameStart = min(energy.count, committedSamples / LiveListen.energyFrameSamples)
        let voiced = LiveListen.voicedFrameCount(in: energy[frameStart...]) >= LiveListen.minVoicedFrames
        let commit = Commit(utterance: start..<sampleCount, voiced: voiced)
        committedSamples = sampleCount
        heardVoice = false
        return commit
    }
}
