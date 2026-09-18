import Foundation
import Testing
@testable import FluisterDemo

struct PartialStabiliserTests {
    @Test func liveUpdatesNeverShrinkTheDisplay() {
        var stabiliser = PartialStabiliser()
        #expect(stabiliser.updateLive("I") == "I")
        #expect(stabiliser.updateLive("I believe that") == "I believe that")
        // A fresh decode restarts from one word; the screen must not collapse.
        #expect(stabiliser.updateLive("I") == "I believe that")
        #expect(stabiliser.updateLive("I believe") == "I believe that")
        #expect(stabiliser.updateLive("I believe that the") == "I believe that the")
    }

    @Test func agreedWordsLockAndSurviveADisagreeingDecode() {
        var stabiliser = PartialStabiliser()
        _ = stabiliser.updateFinal("the majority of russian power is")
        _ = stabiliser.updateFinal("the majority of russian power is neither")
        // "power" is locked; one decode changing its mind is not enough.
        let display = stabiliser.updateFinal("the majority of russian public is neither pro")
        #expect(display.hasPrefix("the majority of russian power is"))
    }

    @Test func repeatedCorrectionIsAdopted() {
        var stabiliser = PartialStabiliser()
        _ = stabiliser.updateFinal("the majority of russian power is")
        _ = stabiliser.updateFinal("the majority of russian power is neither")
        _ = stabiliser.updateFinal("the majority of russian public is neither pro")
        // Second consecutive decode agreeing on "public" confirms the correction.
        let display = stabiliser.updateFinal("the majority of russian public is neither pro war")
        #expect(display == "the majority of russian public is neither pro war")
    }

    @Test func punctuationAndCaseUpgradesAreCorrections() {
        var stabiliser = PartialStabiliser()
        _ = stabiliser.updateFinal("hoe gaan dit")
        _ = stabiliser.updateFinal("hoe gaan dit")
        // Rendering differences do not unlock words on their own...
        _ = stabiliser.updateFinal("Hoe gaan dit?")
        // ...but a repeated rendering is adopted as a correction.
        #expect(stabiliser.updateFinal("Hoe gaan dit?") == "Hoe gaan dit?")
    }

    @Test func lockedPrefixKeepsFirstRenderingWhileTailFollowsLatestDecode() {
        var stabiliser = PartialStabiliser()
        _ = stabiliser.updateFinal("hoe gaan dit met jou")
        let display = stabiliser.updateFinal("Hoe gaan dit, met julle vandag")
        // "hoe gaan dit met" agrees case/punctuation-insensitively and locks
        // with its first rendering; the tail comes from the newest decode.
        #expect(display == "hoe gaan dit met julle vandag")
    }

    @Test func liveUpdatesCannotRewriteTheLockedPrefix() {
        var stabiliser = PartialStabiliser()
        _ = stabiliser.updateFinal("one two three")
        _ = stabiliser.updateFinal("one two three four")
        let display = stabiliser.updateLive("uno dos three four five")
        #expect(display == "one two three four five")
    }

    @Test func shortFinalKeepsWhatIsOnScreen() {
        var stabiliser = PartialStabiliser()
        _ = stabiliser.updateFinal("one two three four")
        _ = stabiliser.updateFinal("one two three four")
        // A truncated decode must not wipe the locked prefix.
        #expect(stabiliser.updateFinal("one two") == "one two three four")
    }

    @Test func resetClearsEverything() {
        var stabiliser = PartialStabiliser()
        _ = stabiliser.updateFinal("one two three")
        _ = stabiliser.updateFinal("one two three")
        stabiliser.reset()
        #expect(stabiliser.display == "")
        #expect(stabiliser.updateLive("fresh start") == "fresh start")
    }
}
