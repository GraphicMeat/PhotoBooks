import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct DeterministicIDTests {

    @Test func sameSeedYieldsSameUUIDSequence() {
        var a = DeterministicIDGenerator(seed: 42)
        var b = DeterministicIDGenerator(seed: 42)
        let idsA = (0..<20).map { _ in a.next() }
        let idsB = (0..<20).map { _ in b.next() }
        #expect(idsA == idsB)
    }

    @Test func differentSeedsDiverge() {
        var a = DeterministicIDGenerator(seed: 1)
        var b = DeterministicIDGenerator(seed: 2)
        #expect(a.next() != b.next())
    }

    @Test func generatedIDsAreDistinct() {
        var generator = DeterministicIDGenerator(seed: 7)
        let ids = (0..<1000).map { _ in generator.next() }
        #expect(Set(ids).count == 1000)
    }

    @Test func stampsVersion4AndRFC4122Variant() {
        var generator = DeterministicIDGenerator(seed: 99)
        for _ in 0..<50 {
            let uuid = generator.next().uuid
            #expect(uuid.6 >> 4 == 0x4)        // version nibble
            #expect(uuid.8 >> 6 == 0b10)       // variant bits
        }
    }
}
