import Foundation
import Testing
@preconcurrency import WhisperKit
@testable import FluisterDemo

struct LiveListenTests {
    @Test func stripsWhisperKitWaitingPlaceholder() {
        #expect(LiveListen.visibleText("Waiting for speech...") == "")
        #expect(LiveListen.visibleText("  waiting for speech...  ") == "")
        #expect(LiveListen.visibleText("one") == "one")
        #expect(LiveListen.visibleText("  two  ") == "two")
        #expect(LiveListen.visibleText("   ") == "")
    }

    @Test func liveDecodingDoesNotClipTheEndOfTheWindow() {
        let options = LiveListen.decodingOptions(language: "af")
        #expect(options.windowClipTime == 0)
        #expect(options.temperatureFallbackCount == 0)
        #expect(options.concurrentWorkerCount == 1)
        #expect(options.chunkingStrategy == ChunkingStrategy.none)
        #expect(options.detectLanguage == false)
        #expect(options.language == "af")
        #expect(options.promptTokens == nil)
    }

    @Test func finalDecodeRetriesWithFallbackButNeverPrompts() {
        let options = LiveListen.finalDecodingOptions(language: "af")
        #expect(options.temperatureFallbackCount == 3)
        // The Fluister fine-tune decodes to empty when given <|startofprev|>
        // conditioning; prompt tokens must stay off for every decode.
        #expect(options.promptTokens == nil)
        #expect(options.language == "af")
        #expect(options.detectLanguage == false)
        #expect(options.windowClipTime == 0)
    }

    @Test func voiceDetectionUsesRecentEnergy() {
        let quiet: [Float] = [0.01, 0.02, 0.04]
        let spoken: [Float] = [0.01, 0.9, 0.02]
        #expect(!LiveListen.isVoice(in: quiet[...]))
        #expect(LiveListen.isVoice(in: spoken[...]))
        #expect(LiveListen.trailingSilenceFrames == 12)
        #expect(LiveListen.minVoicedFrames == 7)
    }

    @Test func segmenterCommitsAnUtteranceAfterTrailingSilence() {
        var segmenter = LiveListenSegmenter()
        let frame = LiveListen.energyFrameSamples
        let silentFrames = LiveListen.trailingSilenceFrames

        // Pure silence: nothing to commit.
        var energy = [Float](repeating: 0.01, count: silentFrames)
        #expect(segmenter.step(sampleCount: energy.count * frame, energy: energy) == nil)

        // A second of speech: voice detected, but no commit while it is running.
        energy += [Float](repeating: 0.9, count: 10)
        #expect(segmenter.step(sampleCount: energy.count * frame, energy: energy) == nil)

        // Trailing silence after speech: the whole span commits as one voiced utterance.
        energy += [Float](repeating: 0.01, count: silentFrames)
        let commit = segmenter.step(sampleCount: energy.count * frame, energy: energy)
        #expect(commit?.voiced == true)
        #expect(commit?.utterance == 0..<(energy.count * frame))
        #expect(segmenter.committedSamples == energy.count * frame)

        // Silence continues: no second commit for the same utterance.
        energy += [Float](repeating: 0.01, count: 2)
        #expect(segmenter.step(sampleCount: energy.count * frame, energy: energy) == nil)
    }

    @Test func segmenterFlagsMicroBlipsAsUnvoiced() {
        var segmenter = LiveListenSegmenter()
        let frame = LiveListen.energyFrameSamples
        let silentFrames = LiveListen.trailingSilenceFrames

        // A blip shorter than minVoicedFrames, then silence.
        var energy = [Float](repeating: 0.9, count: LiveListen.minVoicedFrames - 1)
        #expect(segmenter.step(sampleCount: energy.count * frame, energy: energy) == nil)
        energy += [Float](repeating: 0.01, count: silentFrames)
        let commit = segmenter.step(sampleCount: energy.count * frame, energy: energy)
        #expect(commit != nil)
        #expect(commit?.voiced == false, "a sub-\(LiveListen.minVoicedSeconds)s blip is noise, not a caption")
    }

    @Test func segmenterCountsVoicedFramesPerUtteranceNotPerSession() {
        var segmenter = LiveListenSegmenter()
        let frame = LiveListen.energyFrameSamples
        let silentFrames = LiveListen.trailingSilenceFrames

        // First utterance: long enough to be voiced.
        var energy = [Float](repeating: 0.9, count: 10)
        _ = segmenter.step(sampleCount: energy.count * frame, energy: energy)
        energy += [Float](repeating: 0.01, count: silentFrames)
        #expect(segmenter.step(sampleCount: energy.count * frame, energy: energy)?.voiced == true)

        // Second utterance: a micro blip. Its gate must not be satisfied by the
        // first utterance's voiced frames.
        energy += [Float](repeating: 0.9, count: 2)
        _ = segmenter.step(sampleCount: energy.count * frame, energy: energy)
        energy += [Float](repeating: 0.01, count: silentFrames)
        let second = segmenter.step(sampleCount: energy.count * frame, energy: energy)
        #expect(second?.voiced == false)
    }
}
