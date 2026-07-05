import Foundation

/// Generates UUIDs deterministically from a `SplitMix64` stream. The engine
/// must NEVER call `UUID()` — random IDs would break the byte-stability
/// invariant (same inputs + same seed = identical `Book` through
/// `BookSerializer.encode`).
///
/// The 16 bytes come from two consecutive SplitMix64 outputs; version (4) and
/// variant (RFC 4122) bits are stamped so the IDs are well-formed v4 UUIDs.
struct DeterministicIDGenerator {
    private var rng: SplitMix64

    init(seed: UInt64) {
        self.rng = SplitMix64(seed: seed)
    }

    mutating func next() -> UUID {
        let high = rng.next()
        let low = rng.next()
        func byte(_ value: UInt64, _ index: UInt64) -> UInt8 {
            UInt8(truncatingIfNeeded: value >> (8 * (7 - index)))
        }
        var bytes: [UInt8] = [
            byte(high, 0), byte(high, 1), byte(high, 2), byte(high, 3),
            byte(high, 4), byte(high, 5), byte(high, 6), byte(high, 7),
            byte(low, 0), byte(low, 1), byte(low, 2), byte(low, 3),
            byte(low, 4), byte(low, 5), byte(low, 6), byte(low, 7)
        ]
        bytes[6] = (bytes[6] & 0x0F) | 0x40    // version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80    // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
