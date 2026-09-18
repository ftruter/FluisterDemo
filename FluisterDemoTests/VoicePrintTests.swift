import Foundation
import Testing
@testable import FluisterDemo

struct VoicePrintTests {
    @Test func sameToneMatchesItself() throws {
        let low = tone(hz: 180, seconds: 1.2)
        let again = tone(hz: 180, seconds: 1.2)
        let a = try #require(VoicePrint.embedding(from: low))
        let b = try #require(VoicePrint.embedding(from: again))
        #expect(VoicePrint.cosine(a, b) > 0.98)
    }

    @Test func differentTonesAreFartherApart() throws {
        let low = try #require(VoicePrint.embedding(from: tone(hz: 140, seconds: 1.2)))
        let high = try #require(VoicePrint.embedding(from: tone(hz: 900, seconds: 1.2)))
        #expect(VoicePrint.cosine(low, high) < VoicePrint.cosine(low, low))
        #expect(VoicePrint.cosine(low, high) < 0.97)
    }

    @Test func shortAudioHasNoPrint() {
        #expect(VoicePrint.embedding(from: [0.1, -0.1, 0.2]) == nil)
    }

    private func tone(hz: Double, seconds: Double) -> [Float] {
        let rate = WhisperKitSampleRate.hz
        let n = Int(seconds * rate)
        let step = 2 * Double.pi * hz / rate
        return (0..<n).map { Float(sin(Double($0) * step) * 0.4) }
    }
}
