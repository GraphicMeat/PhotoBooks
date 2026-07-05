import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct AnalyzerUserWeightTests {

    private func ref(_ id: String, importance: Double?, userWeight: Int?) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                 pixelWidth: 4000, pixelHeight: 3000,
                 importance: importance, userWeight: userWeight)
    }

    @Test func userWeightOverridesImportanceWeight() {
        let analyzed = PhotoAnalyzer.analyze([ref("p1", importance: 0.1, userWeight: 5)])
        #expect(analyzed.first?.weight == 5)
    }

    @Test func nilUserWeightUsesImportanceDerivedWeight() {
        let expected = ImportanceWeight.weight(forImportance: 0.9)   // hero => maxWeight
        let analyzed = PhotoAnalyzer.analyze([ref("p1", importance: 0.9, userWeight: nil)])
        #expect(analyzed.first?.weight == expected)
    }

    @Test func userWeightIsClampedToValidRange() {
        let hi = PhotoAnalyzer.analyze([ref("p1", importance: nil, userWeight: 999)])
        #expect(hi.first?.weight == ImportanceWeight.maxWeight)
        let lo = PhotoAnalyzer.analyze([ref("p2", importance: nil, userWeight: -3)])
        #expect(lo.first?.weight == 1)
    }
}
