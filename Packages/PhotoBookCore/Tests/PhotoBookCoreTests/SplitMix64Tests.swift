import Testing
import PhotoBookCore

@Suite struct SplitMix64Tests {

    // Reference vectors computed from the canonical splitmix64.c algorithm.
    @Test func seedZeroKnownAnswers() {
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 0xE220A8397B1DCDAF)
        #expect(rng.next() == 0x6E789E6AA1B965F4)
        #expect(rng.next() == 0x06C45D188009454F)
        #expect(rng.next() == 0xF88BB8A8724C81EC)
        #expect(rng.next() == 0x1B39896A51A8749B)
    }

    @Test func seedOneKnownAnswers() {
        var rng = SplitMix64(seed: 1)
        #expect(rng.next() == 0x910A2DEC89025CC1)
        #expect(rng.next() == 0xBEEB8DA1658EEC67)
        #expect(rng.next() == 0xF893A2EEFB32555E)
    }

    @Test func largeSeedKnownAnswers() {
        var rng = SplitMix64(seed: 0x123456789ABCDEF0)
        #expect(rng.next() == 0x161922C645CE50E8)
        #expect(rng.next() == 0xAD760CAFA1697B60)
        #expect(rng.next() == 0x3501FF44902CA50D)
    }

    @Test func sameSeedProducesSameSequence() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        let seqA = (0..<100).map { _ in a.next() }
        let seqB = (0..<100).map { _ in b.next() }
        #expect(seqA == seqB)
    }

    @Test func differentSeedsDiverge() {
        var a = SplitMix64(seed: 1)
        var b = SplitMix64(seed: 2)
        let seqA = (0..<10).map { _ in a.next() }
        let seqB = (0..<10).map { _ in b.next() }
        #expect(seqA != seqB)
    }
}
