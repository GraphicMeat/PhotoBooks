/// Deterministic pseudo-random number generator (SplitMix64, Vigna 2015).
///
/// This is the engine's ONLY RNG. The determinism invariant — same inputs +
/// same seed = identical `Book` — forbids `SystemRandomNumberGenerator` and
/// `Date()` in engine code paths; seeds are always passed in explicitly.
///
/// Reference implementation: https://prng.di.unimi.it/splitmix64.c
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
