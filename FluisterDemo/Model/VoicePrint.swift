import Accelerate
import Foundation

/// A compact spectral fingerprint of a short speech slice.
///
/// This is not SpeakerKit. Pyannote's public API clusters IDs *inside one clip*,
/// so it cannot name Fred across pauses. Mean log-mel of voiced frames is enough
/// to tell a handful of people apart at a table until we wire a real embedder.
nonisolated enum VoicePrint: Sendable {
    static let bands = 20
    static let matchThreshold: Float = 0.80
    static let fftSize = 512
    static let hop = 160
    static let minVoicedFrames = 6
    static let voiceRMS: Float = 0.01

    static func embedding(from samples: [Float]) -> [Float]? {
        guard samples.count >= hop * minVoicedFrames else { return nil }
        let log2n = vDSP_Length(9)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(setup) }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var accumulator = [Float](repeating: 0, count: bands)
        var voiced = 0
        var frame = [Float](repeating: 0, count: fftSize)
        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)

        var offset = 0
        while offset + fftSize <= samples.count {
            for i in 0..<fftSize {
                frame[i] = samples[offset + i] * window[i]
            }
            var rms: Float = 0
            vDSP_rmsqv(frame, 1, &rms, vDSP_Length(fftSize))
            if rms >= voiceRMS {
                realp.withUnsafeMutableBufferPointer { realBuf in
                    imagp.withUnsafeMutableBufferPointer { imagBuf in
                        var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                        frame.withUnsafeBufferPointer { src in
                            src.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complex in
                                vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(fftSize / 2))
                            }
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
                        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
                        let mel = logMel(magnitudes)
                        vDSP_vadd(accumulator, 1, mel, 1, &accumulator, 1, vDSP_Length(bands))
                    }
                }
                voiced += 1
            }
            offset += hop
        }
        guard voiced >= minVoicedFrames else { return nil }
        var scale = 1 / Float(voiced)
        vDSP_vsmul(accumulator, 1, &scale, &accumulator, 1, vDSP_Length(bands))
        return normalize(accumulator)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return max(-1, min(1, dot))
    }

    static func average(_ a: [Float], _ b: [Float]) -> [Float] {
        guard a.count == b.count else { return a }
        var out = [Float](repeating: 0, count: a.count)
        vDSP_vadd(a, 1, b, 1, &out, 1, vDSP_Length(a.count))
        var half: Float = 0.5
        vDSP_vsmul(out, 1, &half, &out, 1, vDSP_Length(a.count))
        return normalize(out)
    }

    private static func normalize(_ vector: [Float]) -> [Float] {
        var copy = vector
        var norm: Float = 0
        vDSP_svesq(copy, 1, &norm, vDSP_Length(copy.count))
        norm = sqrtf(norm)
        guard norm > 1e-6 else { return copy }
        var scale = 1 / norm
        vDSP_vsmul(copy, 1, &scale, &copy, 1, vDSP_Length(copy.count))
        return copy
    }

    /// 20 triangular bands, 80 Hz–6 kHz, on a 16 kHz / 512-point magnitude spectrum.
    private static func logMel(_ magnitudes: [Float]) -> [Float] {
        let nyquist = Float(WhisperKitSampleRate.hz) / 2
        let binHz = nyquist / Float(magnitudes.count)
        var bands = [Float](repeating: 0, count: Self.bands)
        let lowMel = mel(80)
        let highMel = mel(6000)
        let step = (highMel - lowMel) / Float(Self.bands + 1)
        for b in 0..<Self.bands {
            let left = hz(lowMel + step * Float(b))
            let center = hz(lowMel + step * Float(b + 1))
            let right = hz(lowMel + step * Float(b + 2))
            var energy: Float = 0
            var weightSum: Float = 0
            let start = max(0, Int(left / binHz))
            let end = min(magnitudes.count - 1, Int(right / binHz))
            if start <= end {
                for k in start...end {
                    let f = Float(k) * binHz
                    let w: Float
                    if f < center {
                        w = (f - left) / max(center - left, 1)
                    } else {
                        w = (right - f) / max(right - center, 1)
                    }
                    let weight = max(0, w)
                    energy += magnitudes[k] * weight
                    weightSum += weight
                }
            }
            let mean = weightSum > 0 ? energy / weightSum : 0
            bands[b] = logf(1 + mean)
        }
        return bands
    }

    private static func mel(_ hz: Float) -> Float {
        2595 * log10f(1 + hz / 700)
    }

    private static func hz(_ mel: Float) -> Float {
        700 * (powf(10, mel / 2595) - 1)
    }
}

nonisolated enum WhisperKitSampleRate {
    static let hz: Double = 16_000
}
