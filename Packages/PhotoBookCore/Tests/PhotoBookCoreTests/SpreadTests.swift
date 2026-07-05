import Foundation
import Testing
import PhotoBookCore

@Suite struct SpreadTests {

    // MARK: - slice geometry

    /// A full-canvas panorama (frame {0,0,1,1}) slices into two complementary
    /// half-crops: the left page shows the left half of the source photo, the
    /// right page the right half, and each frame fills its own page.
    @Test func panoramaSpreadSlicesIntoComplementaryHalfCrops() {
        let spread = Spread(
            origin: .template(id: "spread-panorama"),
            photoSlots: [SpreadPhotoSlot(
                frame: NormRect(x: 0, y: 0, width: 1, height: 1),
                photoID: PhotoID(rawValue: "pano"),
                crop: .full)])
        let (left, right) = spread.slice()

        #expect(left.photoSlots.count == 1)
        #expect(right.photoSlots.count == 1)

        let l = left.photoSlots[0]
        let r = right.photoSlots[0]

        // Both photo slots carry the pano photo.
        #expect(l.photoID == PhotoID(rawValue: "pano"))
        #expect(r.photoID == PhotoID(rawValue: "pano"))

        // Each frame fills its own page.
        #expect(l.frame == NormRect(x: 0, y: 0, width: 1, height: 1))
        #expect(r.frame == NormRect(x: 0, y: 0, width: 1, height: 1))

        // Left crop is the left half of the source, right crop the right half.
        #expect(abs(l.crop.x - 0) < 1e-12)
        #expect(abs(l.crop.maxX - 0.5) < 1e-12)
        #expect(abs(r.crop.x - 0.5) < 1e-12)
        #expect(abs(r.crop.maxX - 1.0) < 1e-12)
        // Full vertical extent on both.
        #expect(abs(l.crop.height - 1) < 1e-12)
        #expect(abs(r.crop.height - 1) < 1e-12)
    }

    /// A slot entirely on the right half maps only to the right page; the left
    /// half is empty and the frame is remapped to right-page space.
    @Test func slotEntirelyOnRightHalfMapsToRightPageOnly() {
        let spread = Spread(
            origin: .template(id: "custom"),
            photoSlots: [SpreadPhotoSlot(
                frame: NormRect(x: 0.6, y: 0.1, width: 0.3, height: 0.3),
                photoID: PhotoID(rawValue: "p"),
                crop: .full)])
        let (left, right) = spread.slice()

        #expect(left.photoSlots.isEmpty)
        #expect(right.photoSlots.count == 1)

        let r = right.photoSlots[0]
        // x' = (0.6 - 0.5) / 0.5 = 0.2 ; w' = 0.3 / 0.5 = 0.6
        #expect(abs(r.frame.x - 0.2) < 1e-12)
        #expect(abs(r.frame.width - 0.6) < 1e-12)
        #expect(abs(r.frame.y - 0.1) < 1e-12)
        #expect(abs(r.frame.height - 0.3) < 1e-12)
        // Full crop preserved (slot wholly on one side).
        #expect(r.crop == .full)
    }

    /// A slot wholly on the left half maps only to the left page with the full
    /// crop and a frame remapped to left-page space.
    @Test func slotEntirelyOnLeftHalfMapsToLeftPageOnly() {
        let spread = Spread(
            origin: .template(id: "custom"),
            photoSlots: [SpreadPhotoSlot(
                frame: NormRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                photoID: PhotoID(rawValue: "p"),
                crop: .full)])
        let (left, right) = spread.slice()

        #expect(right.photoSlots.isEmpty)
        #expect(left.photoSlots.count == 1)

        let l = left.photoSlots[0]
        // x' = 0.1 / 0.5 = 0.2 ; w' = 0.3 / 0.5 = 0.6
        #expect(abs(l.frame.x - 0.2) < 1e-12)
        #expect(abs(l.frame.width - 0.6) < 1e-12)
        #expect(l.crop == .full)
    }

    /// Text slots go to whichever half contains their frame center.
    @Test func textSlotGoesToHalfContainingItsCenter() {
        let spread = Spread(
            origin: .template(id: "custom"),
            photoSlots: [],
            textSlots: [
                SpreadTextSlot(frame: NormRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1),
                               text: StyledText(string: "L", pointSizeFactor: 0.04)),
                SpreadTextSlot(frame: NormRect(x: 0.7, y: 0.8, width: 0.2, height: 0.1),
                               text: StyledText(string: "R", pointSizeFactor: 0.04))
            ])
        let (left, right) = spread.slice()

        #expect(left.textSlots.count == 1)
        #expect(right.textSlots.count == 1)
        #expect(left.textSlots[0].text.string == "L")
        #expect(right.textSlots[0].text.string == "R")
        // Left text frame remapped to left-page space: x' = 0.1/0.5 = 0.2
        #expect(abs(left.textSlots[0].frame.x - 0.2) < 1e-12)
        // Right text frame remapped: x' = (0.7-0.5)/0.5 = 0.4
        #expect(abs(right.textSlots[0].frame.x - 0.4) < 1e-12)
    }

    /// Re-slicing the same spread is byte-identical: sliced slot ids are stable.
    @Test func sliceIsDeterministicAndStable() throws {
        let spread = Spread(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            origin: .template(id: "spread-two-up"),
            photoSlots: [
                SpreadPhotoSlot(frame: NormRect(x: 0.04, y: 0.06, width: 0.42, height: 0.88),
                                photoID: PhotoID(rawValue: "a")),
                SpreadPhotoSlot(frame: NormRect(x: 0.54, y: 0.06, width: 0.42, height: 0.88),
                                photoID: PhotoID(rawValue: "b"))
            ])
        let first = spread.slice()
        let second = spread.slice()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func enc(_ half: SlicedHalf) throws -> Data {
            try encoder.encode(half.photoSlots) + encoder.encode(half.textSlots)
        }
        #expect(try enc(first.left) == enc(second.left))
        #expect(try enc(first.right) == enc(second.right))

        // The two photo slots land on opposite pages.
        #expect(first.left.photoSlots.count == 1)
        #expect(first.right.photoSlots.count == 1)
        #expect(first.left.photoSlots[0].photoID == PhotoID(rawValue: "a"))
        #expect(first.right.photoSlots[0].photoID == PhotoID(rawValue: "b"))
    }

    // MARK: - Codable

    @Test func spreadCodableRoundTrip() throws {
        let original = Spread(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            origin: .template(id: "spread-panorama"),
            photoSlots: [SpreadPhotoSlot(
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                frame: .full, photoID: PhotoID(rawValue: "p"), crop: .full)],
            textSlots: [SpreadTextSlot(
                id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
                frame: NormRect(x: 0.1, y: 0.8, width: 0.3, height: 0.1),
                text: StyledText(string: "Caption", pointSizeFactor: 0.04))])
        let decoded = try JSONDecoder().decode(Spread.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func spreadPhotoSlotDefaultsCropToFull() {
        let slot = SpreadPhotoSlot(frame: .full)
        #expect(slot.crop == .full)
        #expect(slot.photoID == nil)
    }

    // MARK: - C4: engine integration

    private var preset: PrintPreset { PresetLibrary.preset(id: "blurb-standard-landscape")! }

    private func ref(_ id: String, width: Int, height: Int, hours: Double?) -> PhotoRef {
        PhotoRef(id: PhotoID(rawValue: id), source: .file(bookmark: Data()),
                 pixelWidth: width, pixelHeight: height,
                 captureDate: hours.map { Date(timeIntervalSinceReferenceDate: $0 * 3600) })
    }

    /// A library with exactly one ultra-wide panorama (aspect 4.0 ≥ 2.2) in its
    /// own time cluster, surrounded by normal photos.
    private func panoFixture() -> [PhotoRef] {
        [
            ref("a1", width: 4000, height: 3000, hours: 0),
            ref("a2", width: 3000, height: 4000, hours: 0.2),
            ref("a3", width: 4000, height: 3000, hours: 0.4),
            ref("pano", width: 8000, height: 2000, hours: 50),   // aspect 4.0, lone cluster
            ref("b1", width: 4000, height: 3000, hours: 100),
            ref("b2", width: 3000, height: 4000, hours: 100.2),
            ref("b3", width: 4000, height: 3000, hours: 100.4)
        ]
    }

    @Test func makeBookAutoPromotesPanoramaIntoSpread() throws {
        let engine = BookEngine()
        let book = engine.makeBook(title: "Trip", photos: panoFixture(), preset: preset,
                                   style: .standard, seed: 7)
        // One spread, holding the pano photo.
        #expect(book.spreads.count == 1)
        let spread = try #require(book.spreads.first)
        #expect(spread.photoSlots.contains { $0.photoID == PhotoID(rawValue: "pano") })

        // Two member pages bound to it: one .left, one .right, both standard.
        let members = book.pages.filter { $0.spreadID == spread.id }
        #expect(members.count == 2)
        #expect(members.allSatisfy { $0.role == .standard })
        #expect(Set(members.compactMap { $0.half }) == [.left, .right])
        // Members are adjacent and in left,right order.
        let leftIdx = try #require(book.pages.firstIndex { $0.spreadID == spread.id && $0.half == .left })
        #expect(book.pages[leftIdx + 1].spreadID == spread.id)
        #expect(book.pages[leftIdx + 1].half == .right)
    }

    @Test func autoPromotedPanoramaIsByteStableAcrossRuns() throws {
        let engine = BookEngine()
        func build() -> Book {
            engine.makeBook(title: "Trip", photos: panoFixture(), preset: preset,
                            style: .standard, seed: 7)
        }
        #expect(try BookSerializer.encode(build()) == BookSerializer.encode(build()))
    }

    @Test func normalPhotosDoNotPromoteToSpreads() {
        let engine = BookEngine()
        let normal = [
            ref("a1", width: 4000, height: 3000, hours: 0),
            ref("a2", width: 3000, height: 4000, hours: 0.2),
            ref("a3", width: 4000, height: 3000, hours: 0.4)
        ]
        let book = engine.makeBook(title: "Normal", photos: normal, preset: preset,
                                   style: .standard, seed: 1)
        #expect(book.spreads.isEmpty)
        #expect(book.pages.allSatisfy { $0.spreadID == nil })
    }

    /// Every placed photo id across standard pages.
    private func placedSet(_ book: Book) -> Set<PhotoID> {
        Set(book.pages.filter { $0.role == .standard }
            .flatMap { $0.photoSlots.compactMap(\.photoID) })
    }

    /// 14 plain (non-pano) photos spread across time so pagination yields
    /// several interior standard pages — gives convertToSpread a facing pair.
    private func plainMultiPageFixture(_ tag: String) -> [PhotoRef] {
        (1...14).map { ref("\(tag)\($0)", width: 4000, height: 3000, hours: Double($0)) }
    }

    @Test func convertToSpreadMergesFacingPairPreservingPhotos() throws {
        let engine = BookEngine()
        // A book with no auto-promoted spreads: plain photos, multiple pages.
        let book = engine.makeBook(title: "Convert", photos: plainMultiPageFixture("c"),
                                   preset: preset, style: .standard, seed: 3)
        // Pick an interior standard page that has a following standard page,
        // neither a spread member.
        let standardIdxs = book.pages.indices.filter {
            book.pages[$0].role == .standard && book.pages[$0].spreadID == nil
        }
        guard let leftIdx = standardIdxs.first(where: { idx in
            idx + 1 < book.pages.count && book.pages[idx + 1].role == .standard
                && book.pages[idx + 1].spreadID == nil
        }) else { Issue.record("no eligible facing pair"); return }

        let leftPageID = book.pages[leftIdx].id
        let beforePlaced = placedSet(book)

        let result = engine.convertToSpread(book, leftPageID: leftPageID, preset: preset, seed: 11)
        #expect(result.spreads.count == 1)
        let spread = try #require(result.spreads.first)
        let members = result.pages.filter { $0.spreadID == spread.id }
        #expect(members.count == 2)
        #expect(Set(members.compactMap { $0.half }) == [.left, .right])
        // The photo SET is preserved.
        #expect(placedSet(result) == beforePlaced)
    }

    @Test func convertToSpreadIneligibleReturnsBookUnchanged() {
        let engine = BookEngine()
        let photos = (1...4).map { ref("d\($0)", width: 4000, height: 3000, hours: Double($0) * 0.1) }
        let book = engine.makeBook(title: "X", photos: photos, preset: preset,
                                   style: .standard, seed: 3)
        // Unknown page id → no-op.
        #expect(engine.convertToSpread(book, leftPageID: UUID(), preset: preset, seed: 1) == book)
        // The cover (pages[0]) is not a standard interior page → no-op.
        #expect(engine.convertToSpread(book, leftPageID: book.pages[0].id, preset: preset, seed: 1) == book)
        // The last standard page has no following partner → no-op.
        let lastStandardID = book.pages.last { $0.role == .standard }!.id
        #expect(engine.convertToSpread(book, leftPageID: lastStandardID, preset: preset, seed: 1) == book)
    }

    @Test func revertSpreadRestoresTwoStandardPagesPreservingPhotos() throws {
        let engine = BookEngine()
        let book = engine.makeBook(title: "Trip", photos: panoFixture(), preset: preset,
                                   style: .standard, seed: 7)
        let spread = try #require(book.spreads.first)
        let beforePlaced = placedSet(book)

        let result = engine.revertSpread(book, spreadID: spread.id, preset: preset, seed: 13)
        #expect(result.spreads.isEmpty)
        // No page still bound to the removed spread.
        #expect(result.pages.allSatisfy { $0.spreadID != spread.id })
        #expect(result.pages.allSatisfy { $0.spreadID == nil })
        // The photo set is preserved.
        #expect(placedSet(result) == beforePlaced)
    }

    @Test func convertThenRevertPreservesPhotoSet() throws {
        let engine = BookEngine()
        let book = engine.makeBook(title: "RT", photos: plainMultiPageFixture("e"),
                                   preset: preset, style: .standard, seed: 3)
        let standardIdxs = book.pages.indices.filter {
            book.pages[$0].role == .standard && book.pages[$0].spreadID == nil
        }
        guard let leftIdx = standardIdxs.first(where: { idx in
            idx + 1 < book.pages.count && book.pages[idx + 1].role == .standard
                && book.pages[idx + 1].spreadID == nil
        }) else { Issue.record("no eligible facing pair"); return }
        let beforePlaced = placedSet(book)

        let converted = engine.convertToSpread(book, leftPageID: book.pages[leftIdx].id,
                                               preset: preset, seed: 11)
        let spreadID = try #require(converted.spreads.first?.id)
        let reverted = engine.revertSpread(converted, spreadID: spreadID, preset: preset, seed: 12)
        #expect(reverted.spreads.isEmpty)
        #expect(placedSet(reverted) == beforePlaced)
    }

    @Test func convertToSpreadIsDeterministic() throws {
        let engine = BookEngine()
        let book = engine.makeBook(title: "Det", photos: plainMultiPageFixture("f"),
                                   preset: preset, style: .standard, seed: 3)
        // The first interior standard page that has a following standard partner.
        let leftID = try #require(book.pages.indices.first { idx in
            idx > 0 && idx + 1 < book.pages.count
                && book.pages[idx].role == .standard && book.pages[idx].spreadID == nil
                && book.pages[idx + 1].role == .standard && book.pages[idx + 1].spreadID == nil
        }.map { book.pages[$0].id })
        let a = try BookSerializer.encode(engine.convertToSpread(book, leftPageID: leftID, preset: preset, seed: 9))
        let b = try BookSerializer.encode(engine.convertToSpread(book, leftPageID: leftID, preset: preset, seed: 9))
        #expect(a == b)
        // And the conversion actually produced a spread.
        #expect(engine.convertToSpread(book, leftPageID: leftID, preset: preset, seed: 9).spreads.count == 1)
    }

    // MARK: - zero-crop spreads

    /// convertToSpread sizes every spread slot to its photo's own aspect, so the
    /// `.full` crop shows the whole photo: frame.aspect · spreadAspect == photoAspect.
    @Test func convertToSpreadProducesZeroCropFrames() throws {
        let engine = BookEngine()
        // Mixed-orientation photos across many hours → several interior pages.
        let photos = (1...8).map { i -> PhotoRef in
            i.isMultiple(of: 2)
                ? ref("zc\(i)", width: 3000, height: 4000, hours: Double(i))   // portrait 0.75
                : ref("zc\(i)", width: 4000, height: 3000, hours: Double(i))   // landscape 1.333
        }
        let book = engine.makeBook(title: "ZC", photos: photos, preset: preset,
                                   style: .standard, seed: 7)
        let standardIdxs = book.pages.indices.filter {
            book.pages[$0].role == .standard && book.pages[$0].spreadID == nil
        }
        guard let leftIdx = standardIdxs.first(where: { idx in
            idx + 1 < book.pages.count && book.pages[idx + 1].role == .standard
                && book.pages[idx + 1].spreadID == nil
        }) else { Issue.record("no eligible facing pair"); return }

        let converted = engine.convertToSpread(book, leftPageID: book.pages[leftIdx].id,
                                               preset: preset, seed: 11)
        let spread = try #require(converted.spreads.first)

        let spreadAspect = 2 * preset.trimSize.aspectRatio
        let aspectByID = Dictionary(uniqueKeysWithValues:
            converted.photoLibrary.map { ($0.id, $0.aspectRatio) })
        #expect(!spread.photoSlots.isEmpty)
        for slot in spread.photoSlots {
            let photoID = try #require(slot.photoID)
            let photoAspect = try #require(aspectByID[photoID])
            #expect(slot.crop == .full)
            #expect(abs(slot.frame.aspectRatio * spreadAspect - photoAspect) < 1e-6,
                    "slot true aspect \(slot.frame.aspectRatio * spreadAspect) != photo \(photoAspect)")
        }
    }

    /// The auto-promoted panorama spread is zero-crop: its single slot is sized
    /// to the pano's aspect (panoFixture's pano is 8000×2000 = aspect 4.0).
    @Test func panoramaSpreadIsZeroCrop() throws {
        let engine = BookEngine()
        let book = engine.makeBook(title: "Pano", photos: panoFixture(), preset: preset,
                                   style: .standard, seed: 7)
        let spread = try #require(book.spreads.first)
        #expect(spread.photoSlots.count == 1)
        let slot = spread.photoSlots[0]
        #expect(slot.photoID == PhotoID(rawValue: "pano"))
        #expect(slot.crop == .full)
        let spreadAspect = 2 * preset.trimSize.aspectRatio
        #expect(abs(slot.frame.aspectRatio * spreadAspect - 4.0) < 1e-6)
    }

    /// Slicing a zero-crop box that straddles the gutter keeps it zero-crop on
    /// each page: the per-page frame's true aspect equals the per-page crop's
    /// pixel aspect, so the whole photo still shows split across the spine.
    @Test func sliceKeepsStraddlingBoxZeroCrop() {
        // A box straddling x = 0.5 whose on-canvas aspect equals the photo's.
        let spreadAspect = 2.5            // double-wide canvas aspect
        let photoAspect = 2.0             // a wide photo
        // Box on the canvas: width chosen so width/height (page space) * spreadAspect == photoAspect.
        // Pick height = 0.4 → box.aspectRatio must be photoAspect/spreadAspect = 0.8 → width = 0.32.
        let box = NormRect(x: 0.34, y: 0.30, width: 0.32, height: 0.40)
        #expect(abs(box.aspectRatio * spreadAspect - photoAspect) < 1e-9)   // sanity: zero-crop input
        #expect(box.x < 0.5 && box.maxX > 0.5)                              // sanity: straddles

        let spread = Spread(origin: .generated(GeneratedLayoutParams(seed: 1, boxes: [box])),
                            photoSlots: [SpreadPhotoSlot(frame: box,
                                                         photoID: PhotoID(rawValue: "w"),
                                                         crop: .full)])
        let (left, right) = spread.slice()
        let l = left.photoSlots[0]
        let r = right.photoSlots[0]

        // Per-page true frame aspect (page aspect = spreadAspect / 2) vs the
        // per-page crop's pixel aspect (= cropWidthFraction * photoAspect, since
        // crop height is full). Equality ⇒ no extra trim on either page.
        let pageAspect = spreadAspect / 2
        let lFrameTrue = l.frame.aspectRatio * pageAspect
        let lCropPixelAspect = (l.crop.width * photoAspect) / l.crop.height
        #expect(abs(lFrameTrue - lCropPixelAspect) < 1e-6,
                "left half cropped beyond zero-crop")

        let rFrameTrue = r.frame.aspectRatio * pageAspect
        let rCropPixelAspect = (r.crop.width * photoAspect) / r.crop.height
        #expect(abs(rFrameTrue - rCropPixelAspect) < 1e-6,
                "right half cropped beyond zero-crop")

        // The two halves' crop widths reconstruct the whole photo.
        #expect(abs((l.crop.width + r.crop.width) - 1.0) < 1e-6)
    }

    @Test func repaginateDoesNotCrossASpread() throws {
        let engine = BookEngine()
        let book = engine.makeBook(title: "Trip", photos: panoFixture(), preset: preset,
                                   style: .standard, seed: 7)
        let spread = try #require(book.spreads.first)
        let memberLeft = try #require(book.pages.first { $0.spreadID == spread.id && $0.half == .left })

        // Find a standard, non-spread page BEFORE the spread to repaginate from.
        let spreadLeftIdx = try #require(book.pages.firstIndex { $0.id == memberLeft.id })
        guard let target = book.pages[1..<spreadLeftIdx].first(where: {
            $0.role == .standard && $0.spreadID == nil && $0.photoSlots.count >= 2
        }) else { return }   // nothing to repaginate before the spread

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let spreadMembersBefore = book.pages.filter { $0.spreadID == spread.id }
        let beforeBytes = try spreadMembersBefore.map { try encoder.encode($0) }

        let result = engine.repaginate(book, fromPageID: target.id, delta: +1, preset: preset, seed: 21)

        // Spread members stay byte-identical (the run never crosses them).
        let spreadMembersAfter = result.pages.filter { $0.spreadID == spread.id }
        let afterBytes = try spreadMembersAfter.map { try encoder.encode($0) }
        #expect(afterBytes == beforeBytes)
        #expect(result.spreads == book.spreads)
    }
}
