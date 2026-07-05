import Testing
@testable import PhotoBookCore

struct ImportanceWeightTests {
    @Test func nilImportanceIsWeightOne() {
        #expect(ImportanceWeight.weight(forImportance: nil) == 1)
    }

    @Test func zeroAndLowImportanceIsWeightOne() {
        #expect(ImportanceWeight.weight(forImportance: 0.0) == 1)
        #expect(ImportanceWeight.weight(forImportance: 0.1) == 1)
    }

    @Test func heroThresholdMapsToPageMax() {
        #expect(ImportanceWeight.weight(forImportance: 0.80) == ImportanceWeight.maxWeight)
        #expect(ImportanceWeight.weight(forImportance: 0.95) == ImportanceWeight.maxWeight)
        #expect(ImportanceWeight.maxWeight == Paginator.maxPhotosPerPage)
    }

    @Test func midImportanceIsBetweenOneAndCap() {
        let w = ImportanceWeight.weight(forImportance: 0.5)
        #expect(w >= 1)
        #expect(w <= ImportanceWeight.midWeightCap)
        #expect(w == 2)   // pin the deterministic value, not just the bounds
    }

    @Test func weightBandsAreStable() {
        // Pin a representative value in each reachable non-hero band plus the
        // hero jump. Mid-band values (not knife-edge transition points, which
        // are float-fragile) guard the formula against retuning regressions.
        #expect(ImportanceWeight.weight(forImportance: 0.10) == 1)
        #expect(ImportanceWeight.weight(forImportance: 0.30) == 2)
        #expect(ImportanceWeight.weight(forImportance: 0.50) == 2)
        #expect(ImportanceWeight.weight(forImportance: 0.70) == 3)
        #expect(ImportanceWeight.weight(forImportance: 0.79) == 3)
        #expect(ImportanceWeight.weight(forImportance: 0.80) == ImportanceWeight.maxWeight)
    }

    @Test func weightIsMonotonicNonDecreasing() {
        var last = 0
        for i in stride(from: 0.0, through: 1.0, by: 0.05) {
            let w = ImportanceWeight.weight(forImportance: i)
            #expect(w >= last)
            last = w
        }
    }

    @Test func outOfRangeImportanceIsClamped() {
        #expect(ImportanceWeight.weight(forImportance: -5.0) == 1)
        #expect(ImportanceWeight.weight(forImportance: 9.0) == ImportanceWeight.maxWeight)
    }
}
