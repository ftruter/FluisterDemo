import AVFAudio
import Foundation
@preconcurrency import WhisperKit

/// How fast we feed sermon audio to Whisper, by lying about the capture sample rate.
///
/// The dataset is slow 16 kHz church speech. A 2× factor treats those samples as if they
/// were captured at 32 kHz, then resamples back to Whisper's 16 kHz — same words in half
/// the time (pitch rises, as it does if you play a tape faster). That is a cheap stand-in
/// for speakers who talk at least twice as quickly.
enum SpeechRate: String, CaseIterable, Sendable {
    case native = "1.00x"
    case brisk = "1.50x"
    case twice = "2.00x"

    var factor: Double {
        switch self {
        case .native: 1.0
        case .brisk: 1.5
        case .twice: 2.0
        }
    }

    /// Per-clip ceiling, asserted by each parameterized eval case. Looser as
    /// speech gets faster; native (0.70) is the conversion-quality bar the old
    /// monolithic eval applied per clip. 2.00x is a stress rate where isolated
    /// clips are known to collapse (measured worst 0.99 over the 500-clip sweep),
    /// so its ceiling only catches hallucination loops, whose insertions push
    /// WER past 1.0. Mean-WER tracking moved to the eval CSV, since the
    /// per-clip tests have no aggregation point.
    var clipWERLimit: Double {
        switch self {
        case .native: 0.70
        case .brisk: 0.85
        case .twice: 1.00
        }
    }
}

enum FasterSpeech {
    static let whisperRate: Double = 16_000

    static func load16k(_ url: URL) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
    }

    /// Replay `samples` (16 kHz) faster by converting through a higher source sample rate.
    static func resample(_ samples: [Float], to rate: SpeechRate) throws -> [Float] {
        if rate == .native { return samples }
        return try convertSampleRate(samples, sourceRate: whisperRate * rate.factor, destRate: whisperRate)
    }

    static func convertSampleRate(_ samples: [Float], sourceRate: Double, destRate: Double) throws -> [Float] {
        guard let srcFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceRate,
            channels: 1,
            interleaved: false
        ), let dstFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: destRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: srcFormat, to: dstFormat) else {
            return linearSpeed(samples, factor: sourceRate / destRate)
        }

        let srcFrames = AVAudioFrameCount(samples.count)
        guard let src = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: srcFrames) else {
            return linearSpeed(samples, factor: sourceRate / destRate)
        }
        src.frameLength = srcFrames
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress, let channel = src.floatChannelData?[0] else { return }
            channel.update(from: base, count: samples.count)
        }

        let dstFrames = AVAudioFrameCount((Double(samples.count) * destRate / sourceRate).rounded(.up))
        guard let dst = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: max(dstFrames, 1)) else {
            return linearSpeed(samples, factor: sourceRate / destRate)
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: dst, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return src
        }
        if status == .error {
            return linearSpeed(samples, factor: sourceRate / destRate)
        }
        let count = Int(dst.frameLength)
        guard count > 0, let channel = dst.floatChannelData?[0] else {
            return linearSpeed(samples, factor: sourceRate / destRate)
        }
        return Array(UnsafeBufferPointer(start: channel, count: count))
    }

    /// Fallback: read the buffer faster with linear interpolation.
    static func linearSpeed(_ samples: [Float], factor: Double) -> [Float] {
        guard factor > 0, !samples.isEmpty else { return samples }
        let outCount = max(1, Int((Double(samples.count) / factor).rounded()))
        var out = [Float](repeating: 0, count: outCount)
        let last = samples.count - 1
        for i in 0..<outCount {
            let src = Double(i) * factor
            let i0 = min(Int(src), last)
            let i1 = min(i0 + 1, last)
            let frac = Float(src - Double(i0))
            out[i] = samples[i0] + (samples[i1] - samples[i0]) * frac
        }
        return out
    }
}
