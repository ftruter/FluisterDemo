import Foundation
import Testing
@preconcurrency import WhisperKit
@testable import FluisterDemo

/// Live decoding runs one Whisper pass per utterance, so a full 500-clip sweep
/// would take hours. A speaker-diverse subset keeps the signal and the runtime.
private let livePipelineClipLimit = 40

/// Scores the pipeline the app actually ships — segmentation on 100 ms energy
/// frames, then one final decode per utterance — instead of the whole-clip
/// decodes the 500-clip eval measures. The gap between the two numbers is what
/// live users experience beyond raw model quality.
///
/// This eval is how we caught that the Fluister fine-tune returns empty text
/// when decodes are conditioned with `<|startofprev|>` prompt tokens (0.41 mean
/// WER prompted vs 0.06 unprompted); keep it honest when changing the policy.
///
/// Lives inside the serialized `AfrikaansASREvalTests` suite and shares its
/// `AfrikaansEvalKit` instance: two multi-GB WhisperKit loads alive at once get
/// the test runner jetsam-killed on device.
extension AfrikaansASREvalTests {
    @Test(.timeLimit(.minutes(60)))
    func livePipelineWERTracksWholeClipDecode() async throws {
        let model = try requireFluisterModel()
        let manifest = try AfrikaansClipManifest.load()
        let clips = manifest.speakerDiverseSample(count: livePipelineClipLimit)
        AfrikaansASRLogging.log.notice(
            "Live-pipeline eval over \(clips.count) of \(manifest.clips.count) clips (capped for runtime; raise livePipelineClipLimit for a full sweep)"
        )

        let files = try await AfrikaansClipCorpus.ensureLocalFiles(for: clips)
        let kit = try await AfrikaansEvalKit.shared(modelFolder: model)
        let language = TranscriptionLanguage.afrikaans.whisperCode

        var liveWERs: [Double] = []
        var wholeWERs: [Double] = []
        for (index, clip) in clips.enumerated() {
            let url = try #require(files[clip])
            let samples = try FasterSpeech.load16k(url)

            let liveText = try await LivePipelineHarness.transcribe(kit: kit, samples: samples, language: language)
            let liveWER = WordErrorRate.ratio(hypothesis: liveText, reference: clip.transcript)
            liveWERs.append(liveWER)

            let wholeResults: [TranscriptionResult] = try await kit.transcribe(
                audioArray: samples,
                decodeOptions: LiveListen.finalDecodingOptions(language: language)
            )
            let wholeText = wholeResults.map(\.text).joined(separator: " ")
            let wholeWER = WordErrorRate.ratio(hypothesis: wholeText, reference: clip.transcript)
            wholeWERs.append(wholeWER)

            AfrikaansASRLogging.log.info(
                "[\(index + 1)/\(clips.count)] live WER \(liveWER, format: .fixed(precision: 3)) whole WER \(wholeWER, format: .fixed(precision: 3)) \(clip.id, privacy: .public)"
            )
        }

        let liveMean = liveWERs.reduce(0, +) / Double(max(liveWERs.count, 1))
        let wholeMean = wholeWERs.reduce(0, +) / Double(max(wholeWERs.count, 1))
        let summary = """
        Live-pipeline Afrikaans eval over \(clips.count) clips:
        live pipeline mean WER \(String(format: "%.3f", liveMean)) (worst \(String(format: "%.3f", liveWERs.max() ?? 1)))
        whole-clip     mean WER \(String(format: "%.3f", wholeMean)) (worst \(String(format: "%.3f", wholeWERs.max() ?? 1)))
        live minus whole gap \(String(format: "%.3f", liveMean - wholeMean))
        """
        AfrikaansASRLogging.log.notice("\(summary, privacy: .public)")
        print(summary)
        Attachment.record(summary, named: "live-pipeline-wer.txt")

        #expect(liveMean < 0.25, "live pipeline mean WER \(liveMean) is too high — the segmentation policy is hurting accuracy")
        #expect(liveMean - wholeMean < 0.10, "live pipeline loses \(liveMean - wholeMean) WER versus whole-clip decoding — the streaming policy is the bottleneck, not the model")
    }
}

/// Streams a clip through the shipped live policy: the same 100 ms buffers and
/// relative-energy bookkeeping as WhisperKit's `AudioProcessor`, the same
/// `LiveListenSegmenter`, and the same final decode per utterance that
/// `Transcriber.listenLoop` commits as a caption.
private enum LivePipelineHarness {
    static func transcribe(kit: WhisperKit, samples: [Float], language: String) async throws -> String {
        var segmenter = LiveListenSegmenter()
        var relativeEnergy: [Float] = []
        var averageEnergy: [Float] = []
        var committed: [String] = []
        let frame = LiveListen.energyFrameSamples
        let finalOptions = LiveListen.finalDecodingOptions(language: language)

        func decodeUtterance(_ range: Range<Int>) async throws {
            let utterance = Array(samples[range])
            let results: [TranscriptionResult] = try await kit.transcribe(audioArray: utterance, decodeOptions: finalOptions)
            let text = LiveListen.visibleText(results.map(\.text).joined(separator: " "))
            guard !text.isEmpty else { return }
            committed.append(text)
        }

        var index = 0
        while index < samples.count {
            let end = min(index + frame, samples.count)
            let buffer = Array(samples[index..<end])
            index = end
            // AudioProcessor.processBuffer scores each buffer against the quietest
            // of its last 20 average energies, including the Float.infinity seed
            // on the first buffer. Replicated bug-for-bug so segmentation matches.
            let reference = averageEnergy.suffix(20).reduce(Float.infinity) { min($0, $1) }
            relativeEnergy.append(AudioProcessor.calculateRelativeEnergy(of: buffer, relativeTo: reference))
            averageEnergy.append(AudioProcessor.calculateAverageEnergy(of: buffer))

            if let commit = segmenter.step(sampleCount: end, energy: relativeEnergy) {
                guard commit.voiced, !commit.utterance.isEmpty else { continue }
                try await decodeUtterance(commit.utterance)
            }
        }

        // A clip can end mid-utterance with no trailing silence; the app commits
        // that tail when the user stops listening, so the harness decodes it too.
        let tailStart = segmenter.committedSamples
        if tailStart < samples.count {
            let tailFrames = relativeEnergy[min(relativeEnergy.count, tailStart / frame)...]
            if LiveListen.voicedFrameCount(in: tailFrames) >= LiveListen.minVoicedFrames {
                try await decodeUtterance(tailStart..<samples.count)
            }
        }
        return committed.joined(separator: " ")
    }
}

