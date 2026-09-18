import Testing

struct WordErrorRateTests {
    @Test func identicalTextIsZero() {
        #expect(WordErrorRate.ratio(hypothesis: "goeie more", reference: "goeie more") == 0)
    }

    @Test func ignoresCaseAndPunctuation() {
        #expect(WordErrorRate.tokens("Goeie môre, vriende!") == ["goeie", "môre", "vriende"])
        #expect(WordErrorRate.ratio(hypothesis: "Goeie môre, vriende!", reference: "goeie môre vriende") == 0)
    }

    @Test func countsSubstitutionsInsertionsAndDeletions() {
        // one substitution: more -> middag
        #expect(WordErrorRate.ratio(hypothesis: "goeie middag", reference: "goeie more") == 0.5)
        // one insertion
        #expect(WordErrorRate.ratio(hypothesis: "die goeie more", reference: "goeie more") == 0.5)
        // one deletion
        #expect(WordErrorRate.ratio(hypothesis: "goeie", reference: "goeie more") == 0.5)
    }

    @Test func keepsAfrikaansApostrophes() {
        #expect(WordErrorRate.tokens("ek is 'n mens") == ["ek", "is", "'n", "mens"])
    }
}
