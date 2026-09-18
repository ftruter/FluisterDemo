import Foundation
import Testing

struct SpeechRateTests {
    @Test func twiceAsFastHalvesDuration() throws {
        let second = [Float](repeating: 0.1, count: 16_000)
        let fast = try FasterSpeech.resample(second, to: .twice)
        #expect(fast.count > 7_000 && fast.count < 9_500)
    }

    @Test func briskRateIsBetweenNativeAndTwice() throws {
        let second = [Float](repeating: 0.1, count: 16_000)
        let brisk = try FasterSpeech.resample(second, to: .brisk)
        let twice = try FasterSpeech.resample(second, to: .twice)
        #expect(brisk.count > twice.count)
        #expect(brisk.count < second.count)
    }

    @Test func nativeRateIsUnchanged() throws {
        let samples: [Float] = [0, 0.5, 1, 0.5, 0]
        #expect(try FasterSpeech.resample(samples, to: .native) == samples)
    }
}
