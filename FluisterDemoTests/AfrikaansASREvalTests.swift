import Foundation
import Testing
@preconcurrency import WhisperKit
@testable import FluisterDemo

/// Proves the Core ML / Metal Fluister-turbo conversion transcribes Afrikaans.
/// Cmd-U downloads the 500-clip corpus (cached after the first run) and scores WER.
///
/// One test case per clip (`arguments:`) so the runner's per-test time allowance
/// applies to a single clip, not the whole sweep — the monolithic version blew
/// the 1-hour limit whenever the WAV cache was cold. Cases share one WhisperKit
/// instance and run `.serialized`; per-clip ceilings are asserted inline, and the
/// per-rate aggregate lives in the flushed-per-row eval CSV for offline mining.
@Suite(.serialized)
struct AfrikaansASREvalTests {
    /// Loud failure when the model is missing. The per-clip cases are disabled
    /// rather than failed in that situation, so a missing model reads as one
    /// failure instead of 500 duplicates.
    @Test func fluisterModelIsInstalled() throws {
        _ = try requireFluisterModel()
    }

    /// The parameterized sweep silently plans zero cases if the manifest fails
    /// to load; this makes that situation a failure instead of a green run.
    @Test func manifestProvidesTheFullClipSelection() {
        #expect(AfrikaansEvalCorpus.clips.count >= AfrikaansClipCorpus.minimumCount)
    }

    @Test(
        .enabled(if: ModelFolder.discover() != nil, "No Fluister-turbo folder. Set FLUISTER_MODEL_FOLDER or run Scripts/link-model.sh."),
        .timeLimit(.minutes(10)),
        arguments: AfrikaansEvalCorpus.clips
    )
    func transcribesClip(_ clip: AfrikaansClip) async throws {
        let model = try requireFluisterModel()
        let kit = try await AfrikaansEvalKit.shared(modelFolder: model)
        let files = try await AfrikaansClipCorpus.ensureLocalFiles(for: [clip])
        let url = try #require(files[clip])
        let native = try FasterSpeech.load16k(url)
        let options = decodingOptions()

        for rate in SpeechRate.allCases {
            let samples = try FasterSpeech.resample(native, to: rate)
            let duration = Double(samples.count) / FasterSpeech.whisperRate
            let (hypothesis, wer) = try await transcribeWER(
                kit: kit,
                samples: samples,
                reference: clip.transcript,
                options: options
            )
            AfrikaansEvalCorpus.recordCSV(
                clip: clip,
                rate: rate,
                durationSeconds: duration,
                wer: wer,
                temperature: options.temperature,
                sourceWAVPath: url.path
            )
            AfrikaansASRLogging.log.info(
                "[\(clip.id, privacy: .public) \(rate.rawValue, privacy: .public)] WER \(wer, format: .fixed(precision: 3)) \(duration, format: .fixed(precision: 2))s hyp=\(hypothesis, privacy: .public)"
            )
            #expect(
                wer < rate.clipWERLimit,
                "\(clip.id) \(rate.rawValue) WER \(wer) is too high for a Fluister conversion check (listen: \(url.path))"
            )
        }
    }
}

func requireFluisterModel() throws -> URL {
    try #require(
        ModelFolder.discover(),
        "No Fluister-turbo folder. This test exists to prove the Metal conversion transcribes Afrikaans. Set FLUISTER_MODEL_FOLDER or run Scripts/link-model.sh."
    )
}

/// The corpus manifest, loaded once to build the parameterized argument list.
nonisolated enum AfrikaansEvalCorpus {
    static let clips: [AfrikaansClip] = (try? AfrikaansClipManifest.load())?.clips ?? []

    /// One CSV for the whole sweep, created on first use. MainActor because
    /// `ASREvalCSV` inherits the test target's MainActor default isolation, and
    /// the eval cases already run there.
    @MainActor private static var csv: ASREvalCSV?

    @MainActor static func recordCSV(
        clip: AfrikaansClip,
        rate: SpeechRate,
        durationSeconds: Double,
        wer: Double,
        temperature: Float,
        sourceWAVPath: String
    ) {
        do {
            let sink = try csv ?? ASREvalCSV()
            csv = sink
            try sink.append(
                index: clip.row,
                rate: rate,
                durationSeconds: durationSeconds,
                wer: wer,
                temperature: temperature,
                sourceWAVPath: sourceWAVPath
            )
        } catch {
            AfrikaansASRLogging.log.error(
                "eval CSV append failed for \(clip.id, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }
}

/// One WhisperKit instance for every eval case. Loading takes minutes and
/// multiple GB, so a per-case load is out of the question — and two instances
/// alive at once gets the runner jetsam-killed on device. `nonisolated(unsafe)`
/// is sound because every user lives in the `.serialized` eval suite.
nonisolated enum AfrikaansEvalKit {
    nonisolated(unsafe) private static var kit: WhisperKit?

    static func shared(modelFolder: URL) async throws -> WhisperKit {
        if let kit { return kit }
        AfrikaansASRLogging.log.notice("loading WhisperKit from \(modelFolder.path, privacy: .public)")
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            prewarm: false,
            download: false
        )
        let fresh = try await WhisperKit(config)
        guard fresh.tokenizer != nil else { throw TranscriberError.missingTokenizer }
        kit = fresh
        return fresh
    }
}

private func decodingOptions() -> DecodingOptions {
    DecodingOptions(
        verbose: false,
        task: .transcribe,
        language: TranscriptionLanguage.afrikaans.whisperCode,
        temperature: 0,
        usePrefillPrompt: true,
        detectLanguage: false,
        skipSpecialTokens: true,
        wordTimestamps: false
    )
}

private func transcribeWER(
    kit: WhisperKit,
    samples: [Float],
    reference: String,
    options: DecodingOptions
) async throws -> (hypothesis: String, wer: Double) {
    let results: [TranscriptionResult] = try await kit.transcribe(
        audioArray: samples,
        decodeOptions: options
    )
    let hypothesis = results.map(\.text).joined(separator: " ")
    return (hypothesis, WordErrorRate.ratio(hypothesis: hypothesis, reference: reference))
}
