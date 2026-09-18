import Foundation
import Testing
@testable import FluisterDemo

struct NameParserTests {
    @Test func readsEnglishIntroductions() {
        #expect(NameParser.displayName(from: "Hello I'm Fred") == "Fred")
        #expect(NameParser.displayName(from: "Hi I am Susan") == "Susan")
        #expect(NameParser.displayName(from: "my name is jean-pierre") == "Jean-pierre")
        #expect(NameParser.displayName(from: "it's Mary") == "Mary")
    }

    @Test func readsAfrikaansIntroductions() {
        #expect(NameParser.displayName(from: "hallo ek is Fred") == "Fred")
        #expect(NameParser.displayName(from: "my naam is Annelie") == "Annelie")
        #expect(NameParser.displayName(from: "dit is Koos") == "Koos")
    }

    @Test func acceptsABareName() {
        #expect(NameParser.displayName(from: "Fred") == "Fred")
        #expect(NameParser.displayName(from: "  mary-jane  ") == "Mary-jane")
    }

    @Test func rejectsNonNames() {
        #expect(NameParser.displayName(from: "I'm tired") == nil)
        #expect(NameParser.displayName(from: "how are you") == nil)
        #expect(NameParser.displayName(from: "ja") == nil)
        #expect(NameParser.displayName(from: "") == nil)
    }
}
