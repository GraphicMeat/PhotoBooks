import Testing
@testable import PhotoBookCore
import Foundation

@Suite struct LayoutOptionsTests {
    static let preset = PresetLibrary.preset(id: "blurb-standard-landscape")!

    private func ref(_ id: String, hours: Double) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                 pixelWidth: 4000, pixelHeight: 3000,
                 captureDate: Date(timeIntervalSinceReferenceDate: hours * 3600))
    }
    private func book() -> Book {
        let photos = (0..<8).map { ref("p\($0)", hours: Double($0) * 0.3) }
        return BookEngine().makeBook(title: "LO", photos: photos,
                                     preset: Self.preset, style: .standard, seed: 3)
    }

    @Test func optionsCoverFeasibleCountsDescending() {
        let engine = BookEngine()
        let b = book()
        // First interior standard page with a downstream run.
        let page = b.pages.first { $0.role == .standard }!
        let opts = engine.layoutOptions(for: page.id, in: b, preset: Self.preset)
        #expect(!opts.isEmpty)
        let counts = opts.map(\.count)
        #expect(counts == counts.sorted(by: >))          // descending
        #expect(counts.allSatisfy { $0 >= 1 && $0 <= 9 })
        #expect(opts.allSatisfy { !$0.candidates.isEmpty })
    }

    @Test func coverPageHasNoOptions() {
        let engine = BookEngine()
        let b = book()
        let cover = b.pages.first { $0.role == .cover }!
        #expect(engine.layoutOptions(for: cover.id, in: b, preset: Self.preset).isEmpty)
    }

    @Test func lockedPageHasNoOptions() {
        let engine = BookEngine()
        var b = book()
        let idx = b.pages.firstIndex { $0.role == .standard }!
        b.pages[idx].isLocked = true
        #expect(engine.layoutOptions(for: b.pages[idx].id, in: b, preset: Self.preset).isEmpty)
    }

    @Test func unknownPageHasNoOptions() {
        let engine = BookEngine()
        #expect(engine.layoutOptions(for: UUID(), in: book(), preset: Self.preset).isEmpty)
    }

    @Test func stripOffersColumnAndGridPerCount() {
        let engine = BookEngine()
        let b = book()                                  // 8 landscape photos
        let page = b.pages.first { $0.role == .standard }!
        let opts = engine.layoutOptions(for: page.id, in: b, preset: Self.preset)
        // Pick a count that supports columns (>= 2). Prefer >= 6, else any >= 2.
        let group = opts.first { $0.count >= 6 } ?? opts.first { $0.count >= 2 }!
        let families = Set(group.candidates.map(\.family))
        #expect(families.contains(.masonry))
        #expect(families.contains(.grid))
        #expect(families.contains(.justified))
        let counts = Dictionary(grouping: group.candidates, by: \.family).mapValues(\.count)
        #expect((counts[.justified] ?? 0) <= 3)
        #expect((counts[.masonry] ?? 0) <= 2)
        #expect((counts[.grid] ?? 0) <= 2)
    }

    @Test func layoutCandidateDefaultsToJustifiedFamily() {
        let c = LayoutCandidate(origin: .generated(GeneratedLayoutParams(seed: 1, boxes: [.full])),
                                photoSlotFrames: [.full], textSlotFrames: [])
        #expect(c.family == .justified)
        let m = LayoutCandidate(origin: .generated(GeneratedLayoutParams(seed: 1, boxes: [.full])),
                                photoSlotFrames: [.full], textSlotFrames: [], family: .masonry)
        #expect(m.family == .masonry)
    }
}
