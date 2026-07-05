import Foundation
import Testing
@testable import PhotoBookCore

@Suite struct PhotoAnalyzerTests {

    private func ref(_ id: String, width: Int = 4000, height: Int = 3000,
                     date: Date? = nil) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                 pixelWidth: width, pixelHeight: height, captureDate: date)
    }

    private func date(hours: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: hours * 3600)
    }

    @Test func sortsChronologically() {
        let photos = [
            ref("c", date: date(hours: 3)),
            ref("a", date: date(hours: 1)),
            ref("b", date: date(hours: 2))
        ]
        let analyzed = PhotoAnalyzer.analyze(photos)
        #expect(analyzed.map(\.id.rawValue) == ["a", "b", "c"])
    }

    @Test func equalDatesKeepLibraryOrder() {
        let same = date(hours: 5)
        let photos = [ref("first", date: same), ref("second", date: same), ref("third", date: same)]
        let analyzed = PhotoAnalyzer.analyze(photos)
        #expect(analyzed.map(\.id.rawValue) == ["first", "second", "third"])
    }

    @Test func nilDatePhotosKeepLibraryOrderAtEnd() {
        let photos = [
            ref("undated-1"),
            ref("dated", date: date(hours: 1)),
            ref("undated-2")
        ]
        let analyzed = PhotoAnalyzer.analyze(photos)
        #expect(analyzed.map(\.id.rawValue) == ["dated", "undated-1", "undated-2"])
    }

    @Test func clustersSplitOnGapsOverThreeHours() {
        let photos = [
            ref("a", date: date(hours: 0)),
            ref("b", date: date(hours: 1)),      // +1h    → same cluster
            ref("c", date: date(hours: 4.5)),    // +3.5h  → NEW cluster
            ref("d", date: date(hours: 5)),      // +0.5h  → same cluster
            ref("e", date: date(hours: 9))       // +4h    → NEW cluster
        ]
        let analyzed = PhotoAnalyzer.analyze(photos)
        #expect(analyzed.map(\.clusterIndex) == [0, 0, 1, 1, 2])
    }

    @Test func gapOfExactlyThreeHoursStaysInCluster() {
        // Threshold is strictly greater-than: a 3h00m gap does NOT split.
        let photos = [ref("a", date: date(hours: 0)), ref("b", date: date(hours: 3))]
        let analyzed = PhotoAnalyzer.analyze(photos)
        #expect(analyzed.map(\.clusterIndex) == [0, 0])
    }

    @Test func undatedTailFormsItsOwnCluster() {
        let photos = [
            ref("dated-1", date: date(hours: 0)),
            ref("dated-2", date: date(hours: 1)),
            ref("undated-1"),
            ref("undated-2")
        ]
        let analyzed = PhotoAnalyzer.analyze(photos)
        #expect(analyzed.map(\.clusterIndex) == [0, 0, 1, 1])
    }

    @Test func allUndatedIsOneClusterInLibraryOrder() {
        let photos = [ref("x"), ref("y"), ref("z")]
        let analyzed = PhotoAnalyzer.analyze(photos)
        #expect(analyzed.map(\.id.rawValue) == ["x", "y", "z"])
        #expect(analyzed.map(\.clusterIndex) == [0, 0, 0])
    }

    @Test func orientationClassification() {
        // 4000×3000 = 1.333 → landscape; 3000×4000 = 0.75 → portrait.
        #expect(PhotoAnalyzer.analyze([ref("l")])[0].orientation == .landscape)
        #expect(PhotoAnalyzer.analyze([ref("p", width: 3000, height: 4000)])[0].orientation == .portrait)
        // Exactly 1.0 → square.
        #expect(PhotoAnalyzer.analyze([ref("s", width: 2000, height: 2000)])[0].orientation == .square)
        // Inside the 5% band: 2080/2000 = 1.04 and 2000/2080 ≈ 0.962 → square.
        #expect(PhotoAnalyzer.analyze([ref("s2", width: 2080, height: 2000)])[0].orientation == .square)
        #expect(PhotoAnalyzer.analyze([ref("s3", width: 2000, height: 2080)])[0].orientation == .square)
        // Outside the band: 2120/2000 = 1.06 → landscape; inverse → portrait.
        #expect(PhotoAnalyzer.analyze([ref("l2", width: 2120, height: 2000)])[0].orientation == .landscape)
        #expect(PhotoAnalyzer.analyze([ref("p2", width: 2000, height: 2120)])[0].orientation == .portrait)
    }

    @Test func emptyInputYieldsEmptyOutput() {
        #expect(PhotoAnalyzer.analyze([]).isEmpty)
    }

    @Test func analyzeDerivesWeightFromImportance() {
        let hero = PhotoRef(id: PhotoID(rawValue: "hero"),
                            source: .file(bookmark: Data()),
                            pixelWidth: 4000, pixelHeight: 3000,
                            captureDate: Date(timeIntervalSince1970: 1),
                            importance: 0.9)
        let plain = PhotoRef(id: PhotoID(rawValue: "plain"),
                             source: .file(bookmark: Data()),
                             pixelWidth: 4000, pixelHeight: 3000,
                             captureDate: Date(timeIntervalSince1970: 2),
                             importance: nil)
        let analyzed = PhotoAnalyzer.analyze([hero, plain])
        let byID = Dictionary(uniqueKeysWithValues: analyzed.map { ($0.id, $0) })
        #expect(byID[PhotoID(rawValue: "hero")]!.weight == ImportanceWeight.maxWeight)
        #expect(byID[PhotoID(rawValue: "plain")]!.weight == 1)
    }
}
