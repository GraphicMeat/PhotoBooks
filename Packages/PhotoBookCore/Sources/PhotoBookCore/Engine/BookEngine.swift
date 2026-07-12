import Foundation

public enum ReshuffleScope: Equatable, Sendable {
    case book
    case page(UUID)
}

/// The hybrid layout engine: analyze → sequence → paginate → candidates from
/// every provider → provider-blind scoring → assembled `Book`.
///
/// Determinism: every UUID comes from `DeterministicIDGenerator`, every
/// layout decision from `SplitMix64` — both fed only by the caller's seed.
/// Same inputs + same seed = byte-identical `Book` through
/// `BookSerializer.encode`.
public struct BookEngine: Sendable {

    /// A single photo this wide (pixel aspect ratio) or wider is auto-promoted
    /// to a full 2-page panorama spread during `makeBook`.
    public static let panoramaAspectThreshold = 2.2

    /// A single photo at or above this aspect ratio AND with importance
    /// ≥ `ImportanceWeight.heroThreshold` is auto-promoted to a full 2-page
    /// hero spread during `makeBook` (an ADDITIONAL trigger to the panorama
    /// path, which the panorama branch — checked first — already covers for
    /// aspect ≥ `panoramaAspectThreshold`).
    public static let heroAspectThreshold = 1.2

    /// Minimum number of standard (non-spread) interior pages that must be
    /// emitted after an auto-promoted hero spread before the next hero may be
    /// promoted. The first hero has no spacing requirement.
    public static let heroSpreadMinSpacing = 6

    private let providers: [any LayoutProvider]
    private let scorer: LayoutScorer
    private let spreadTemplates: SpreadTemplateProvider

    public init(providers: [any LayoutProvider], scorer: LayoutScorer) {
        self.providers = providers
        self.scorer = scorer
        self.spreadTemplates = SpreadTemplateProvider()
    }

    public init() {
        // Justified zero-crop packing is the default interior layout: slots are
        // sized to each photo's own aspect, so nothing is cropped or zoomed.
        self.init(providers: [JustifiedProvider(), MasonryProvider(), GridProvider()],
                  scorer: LayoutScorer())
    }

    // MARK: - makeBook

    public func makeBook(title: String, photos: [PhotoRef], preset: PrintPreset,
                         style: BookStyle, seed: UInt64) -> Book {
        var book = Book(title: title, presetID: preset.id, style: style)
        book.photoLibrary = photos
        let analyzed = PhotoAnalyzer.analyze(photos)
        guard !analyzed.isEmpty else { return book }

        var master = SplitMix64(seed: seed)
        var ids = DeterministicIDGenerator(seed: master.next())

        // Cover: pages[0], full-bleed lead photo + title text zone. The lead
        // photo is the chronologically first (analyzed[0]); v1 default per
        // spec — the user can replace it in the editor.
        book.pages.append(makeCoverPage(photo: analyzed[0], title: title, ids: &ids))

        // Interior: paginate the full sequence (the lead photo also opens
        // the interior — duplicating the cover image inside is standard
        // photobook practice and keeps placeRemaining semantics simple).
        var previousPage: Page? = nil
        // Hero-spread caps: at most one auto-hero per time-cluster, and at least
        // `heroSpreadMinSpacing` standard pages between hero spreads. Both are
        // derived purely from photo data + emission order, so a book with no
        // qualifying hero consumes exactly the seeds/ids it did pre-B4.
        var heroClusters = Set<Int>()
        var pagesSinceHero = Self.heroSpreadMinSpacing   // first hero: no spacing gate
        for indices in packedGroups(analyzed, preset: preset, style: style) {
            let groupPhotos = indices.map { analyzed[$0] }
            // Auto-promote a lone ultra-wide panorama to a 2-page spread. The
            // master seed is consumed UNCONDITIONALLY for this group either way
            // so downstream pages stay byte-stable regardless of the branch.
            let groupSeed = master.next()
            if groupPhotos.count == 1,
               groupPhotos[0].ref.aspectRatio >= Self.panoramaAspectThreshold {
                let (spread, members) = buildSpread(
                    photos: groupPhotos, preset: preset, style: style, ids: &ids)
                book.spreads.append(spread)
                book.pages.append(contentsOf: members)
                previousPage = members.last
                continue
            }
            // Auto-promote a lone hero (importance ≥ threshold AND near-landscape)
            // to a full spread, subject to the per-cluster + spacing caps. Panorama
            // spreads (above) are a separate mechanism: they neither consume a
            // hero-cluster slot nor reset the spacing counter.
            if groupPhotos.count == 1,
               isHeroCandidate(groupPhotos[0]),
               !heroClusters.contains(groupPhotos[0].clusterIndex),
               pagesSinceHero >= Self.heroSpreadMinSpacing {
                let (spread, members) = buildSpread(
                    photos: groupPhotos, preset: preset, style: style, ids: &ids)
                book.spreads.append(spread)
                book.pages.append(contentsOf: members)
                previousPage = members.last
                heroClusters.insert(groupPhotos[0].clusterIndex)
                pagesSinceHero = 0
                continue
            }
            let page = makeStandardPage(photos: groupPhotos, preset: preset,
                                        style: style, needsTextZone: false,
                                        seed: groupSeed, previousPage: previousPage,
                                        ids: &ids)
            book.pages.append(page)
            previousPage = page
            pagesSinceHero += 1
        }

        // Back cover: minted LAST so every existing page ID stays byte-stable.
        if let backIdx = backCoverIndex(in: analyzed) {
            book.backCover = makeBackCoverPage(photo: analyzed[backIdx], ids: &ids)
        }
        return book
    }

    /// True when a lone photo qualifies for hero-spread promotion: content
    /// importance at or above `ImportanceWeight.heroThreshold` AND a
    /// near-landscape aspect (≥ `heroAspectThreshold`). Pure — no seeds/ids.
    private func isHeroCandidate(_ photo: AnalyzedPhoto) -> Bool {
        (photo.ref.importance ?? 0) >= ImportanceWeight.heroThreshold
            && photo.ref.aspectRatio >= Self.heroAspectThreshold
    }

    // MARK: - Spread construction

    /// Builds a `Spread` from `photos` plus its two sliced member `Page`s, with
    /// every slot sized to its photo's own aspect (zero crop) via
    /// `JustifiedSpreadLayout`. IDs are drawn from `ids` in a fixed order —
    /// spread id, left page id, right page id — and the photo slot ids are
    /// re-minted deterministically from the spread id, so the result is
    /// byte-stable. Spreads carry no text zone in v1.
    private func buildSpread(photos: [AnalyzedPhoto], preset: PrintPreset,
                             style: BookStyle,
                             ids: inout DeterministicIDGenerator) -> (Spread, [Page]) {
        let spreadID = ids.next()

        // Zero-crop frames on the double-wide canvas (spine at x = 0.5). Honor
        // the book edge style the same way JustifiedProvider does: no outer
        // margin unless framed, no gutter under borderless. Spreads are built
        // before member pages exist, so book-level `style.edgeStyle` is the
        // source (there is no per-page override yet to resolve).
        let margin = style.edgeStyle.hasOuterMargin ? style.pageMargin : 0
        let gutter = style.edgeStyle.keepsGutter ? style.gutter : 0
        let content = NormRect.full.inset(by: margin)
        let spreadAspect = 2 * preset.trimSize.aspectRatio
        let frames = JustifiedSpreadLayout.boxes(
            aspects: photos.map(\.ref.aspectRatio),
            content: content, spreadAspect: spreadAspect, gutter: gutter)

        // Bind photos into their boxes in order; crop stays .full (now matches
        // the frame aspect, so the whole photo shows). Serialize the boxes in
        // the origin so reopening never re-lays out.
        var photoSlots: [SpreadPhotoSlot] = []
        for (index, frame) in frames.enumerated() {
            // Bias the crop off the gutter when this slot straddles the spine
            // and the photo has a known salient center; otherwise keep .full.
            // Pure + deterministic — consumes no seeds/ids.
            let ref = photos[index].ref
            let crop = GutterSafeCrop.crop(
                slotFrame: frame,
                photoAspect: ref.aspectRatio,
                spreadAspect: spreadAspect,
                salientCenter: ref.salientCenter) ?? .full
            photoSlots.append(SpreadPhotoSlot(
                frame: frame,
                photoID: photos[index].id,
                crop: crop))
        }
        let origin = LayoutOrigin.generated(
            GeneratedLayoutParams(seed: Spread.stableSeed(for: spreadID), boxes: frames))

        // Re-mint the spread photo slot ids deterministically from the spread id.
        var slotIDs = DeterministicIDGenerator(seed: Spread.stableSeed(for: spreadID) &+ 0x5170A11)
        for i in photoSlots.indices { photoSlots[i].id = slotIDs.next() }

        let spread = Spread(id: spreadID, origin: origin,
                            photoSlots: photoSlots, textSlots: [])
        let sliced = spread.slice()
        let leftID = ids.next()
        let rightID = ids.next()
        let leftPage = Page(id: leftID, role: .standard, origin: origin,
                            photoSlots: sliced.left.photoSlots,
                            textSlots: sliced.left.textSlots,
                            isLocked: false, spreadID: spreadID, half: .left)
        let rightPage = Page(id: rightID, role: .standard, origin: origin,
                             photoSlots: sliced.right.photoSlots,
                             textSlots: sliced.right.textSlots,
                             isLocked: false, spreadID: spreadID, half: .right)
        return (spread, [leftPage, rightPage])
    }

    /// The cover layout is fixed (full-bleed hero + centered title band),
    /// not provider-chosen; the symbolic origin id records that. Renderers
    /// read `photoSlots`/`textSlots` directly and never re-resolve origins.
    private func makeCoverPage(photo: AnalyzedPhoto, title: String,
                               ids: inout DeterministicIDGenerator) -> Page {
        Page(id: ids.next(),
             role: .cover,
             origin: .template(id: "cover-hero"),
             photoSlots: [PhotoSlot(id: ids.next(), frame: .full,
                                    photoID: photo.id, crop: .full, isLocked: false)],
             textSlots: [TextSlot(id: ids.next(),
                                  frame: NormRect(x: 0.08, y: 0.40, width: 0.84, height: 0.20),
                                  text: StyledText(string: title, fontName: "",
                                                   pointSizeFactor: 0.07,
                                                   colorHex: "#FFFFFF", alignment: .center),
                                  isLocked: false)],
             isLocked: false)
    }

    /// The back cover: a full-bleed hero, no text (the title lives on the front
    /// and the spine). Symbolic origin, same as the front cover.
    private func makeBackCoverPage(photo: AnalyzedPhoto,
                                   ids: inout DeterministicIDGenerator) -> Page {
        Page(id: ids.next(),
             role: .backCover,
             origin: .template(id: "backcover-hero"),
             photoSlots: [PhotoSlot(id: ids.next(), frame: .full,
                                    photoID: photo.id, crop: .full, isLocked: false)],
             textSlots: [],
             isLocked: false)
    }

    /// Index into `analyzed` of the back-cover photo: highest `importance`
    /// (nil → 0) among all photos EXCEPT the front (`analyzed[0]`), earliest on
    /// ties. `nil` when there is no second photo.
    private func backCoverIndex(in analyzed: [AnalyzedPhoto]) -> Int? {
        guard analyzed.count >= 2 else { return nil }
        var best = 1
        for i in 2..<analyzed.count {
            if (analyzed[i].ref.importance ?? 0) > (analyzed[best].ref.importance ?? 0) {
                best = i    // strict `>` keeps the earliest index on ties
            }
        }
        return best
    }

    // MARK: - reshuffle

    /// Re-picks layouts (NOT pagination — photo→page grouping is stable) for
    /// every reshuffleable page in scope, with a new seed. A page is
    /// reshuffleable only when neither it nor any of its slots is locked —
    /// the conservative reading of "locked pages/slots untouched". Manual
    /// edits auto-lock their slot (spec), so user work always survives.
    public func reshuffle(_ book: Book, scope: ReshuffleScope, preset: PrintPreset,
                          seed: UInt64) -> Book {
        var result = book
        var master = SplitMix64(seed: seed)
        var ids = DeterministicIDGenerator(seed: master.next())
        let analyzedByID = analyzedLibrary(of: book)

        for index in result.pages.indices {
            let page = result.pages[index]
            // Consume one seed per page UNCONDITIONALLY so a page's new seed
            // never depends on which other pages are locked or in scope.
            let pageSeed = master.next()

            guard page.role == .standard else { continue }
            if case .page(let targetID) = scope, page.id != targetID { continue }
            guard isReshuffleable(page) else { continue }

            let photos = page.photoSlots.compactMap { slot in
                slot.photoID.flatMap { analyzedByID[$0] }
            }
            guard !photos.isEmpty else { continue }

            let previous = index > 0 ? result.pages[index - 1] : nil
            var newPage = makeStandardPage(photos: photos, preset: preset, style: book.style,
                                           needsTextZone: !page.textSlots.isEmpty,
                                           seed: pageSeed, previousPage: previous, ids: &ids,
                                           pageEdgeStyle: page.edgeStyleOverride)
            newPage.id = page.id        // page identity survives (undo, thumbnails)
            newPage.edgeStyleOverride = page.edgeStyleOverride  // preserve override
            newPage.backgroundColorHex = page.backgroundColorHex  // preserve bg override
            result.pages[index] = newPage
        }
        return result
    }

    private func isReshuffleable(_ page: Page) -> Bool {
        !page.isLocked
            && page.photoSlots.allSatisfy { !$0.isLocked }
            && page.textSlots.allSatisfy { !$0.isLocked }
    }

    // MARK: - alternatives

    /// Pre-scored candidates for one page, best first. Seeded by the page's
    /// own identity, so the "try next layout" strip is stable across calls.
    public func alternatives(for pageID: UUID, in book: Book, preset: PrintPreset,
                             limit: Int) -> [LayoutCandidate] {
        guard limit > 0,
              let index = book.pages.firstIndex(where: { $0.id == pageID }) else { return [] }
        let page = book.pages[index]
        let analyzedByID = analyzedLibrary(of: book)
        let photos = page.photoSlots.compactMap { slot in
            slot.photoID.flatMap { analyzedByID[$0] }
        }
        guard !photos.isEmpty else { return [] }

        let effectiveEdgeStyle = page.edgeStyleOverride ?? book.style.edgeStyle
        let context = LayoutContext(pageSize: preset.trimSize, style: book.style,
                                    needsTextZone: !page.textSlots.isEmpty,
                                    seed: Self.stableSeed(for: pageID),
                                    edgeStyle: effectiveEdgeStyle)
        let previous = index > 0 ? book.pages[index - 1] : nil
        return scoredCandidates(photos: photos, context: context, previousPage: previous)
            .prefix(limit)
            .map(\.candidate)
    }

    // MARK: - edgeStyleCandidate

    /// Best layout candidate for the page's CURRENT photo count under an
    /// explicit `edgeStyle`. Used to re-frame a page to another edge mode even
    /// when it is locked — an explicit edge-style change is a deliberate
    /// instruction that overrides the reshuffle lock gate. Returns `nil` for an
    /// unknown id or a page with no bound photos.
    public func edgeStyleCandidate(for pageID: UUID, in book: Book,
                                   edgeStyle: EdgeStyle, preset: PrintPreset) -> LayoutCandidate? {
        guard let idx = book.pages.firstIndex(where: { $0.id == pageID }) else { return nil }
        let page = book.pages[idx]
        let analyzedByID = analyzedLibrary(of: book)
        let photos = page.photoSlots.compactMap { slot in
            slot.photoID.flatMap { analyzedByID[$0] }
        }
        guard !photos.isEmpty else { return nil }
        let context = LayoutContext(pageSize: preset.trimSize, style: book.style,
                                    needsTextZone: !page.textSlots.isEmpty,
                                    seed: Self.stableSeed(for: pageID),
                                    edgeStyle: edgeStyle)
        let previous = idx > 0 ? book.pages[idx - 1] : nil
        return scoredCandidates(photos: photos, context: context,
                                previousPage: previous).first?.candidate
    }

    // MARK: - repaginate

    /// Adjusts the photo count on the page identified by `pageID` by `delta`
    /// (any non-zero integer; the resulting first-page count is clamped to
    /// `1...min(maxPhotosPerPage, runPhotoCount)`) and reflows the contiguous
    /// downstream run of reshuffleable standard pages. Locked pages, cover
    /// pages, and pages above `pageID` are never touched. Returns `book`
    /// unchanged for any no-op condition.
    public func repaginate(_ book: Book, fromPageID pageID: UUID, delta: Int,
                           preset: PrintPreset, seed: UInt64) -> Book {
        // Step 1 — find the target page; it must be standard, reshuffleable,
        // and NOT a spread member (a spread is never re-paginated through).
        guard let idx = book.pages.firstIndex(where: { $0.id == pageID }),
              book.pages[idx].role == .standard,
              book.pages[idx].spreadID == nil,
              isReshuffleable(book.pages[idx]) else { return book }

        // Step 2 — extend downstream run [idx, end). The run stops at any spread
        // member so a spread bounds the run and is never re-paginated through.
        var end = idx
        while end < book.pages.count,
              book.pages[end].role == .standard,
              book.pages[end].spreadID == nil,
              isReshuffleable(book.pages[end]) {
            end += 1
        }

        // Step 3 — collect run photos in order.
        let analyzedByID = analyzedLibrary(of: book)
        let runPhotos: [AnalyzedPhoto] = book.pages[idx..<end].flatMap { page in
            page.photoSlots.compactMap { slot in
                slot.photoID.flatMap { analyzedByID[$0] }
            }
        }

        // Step 4 — compute newFirst; guard no-op conditions.
        let currentFirst = book.pages[idx].photoSlots.count
        if delta > 0 && runPhotos.count <= currentFirst { return book }
        if delta < 0 && currentFirst == 1 { return book }

        let newFirst = min(Paginator.maxPhotosPerPage, runPhotos.count,
                           max(1, currentFirst + delta))
        if newFirst == currentFirst { return book }

        // Step 5 — re-paginate the run with the first group pinned.
        let remainder = Array(runPhotos[newFirst...])
        let remainderGroups = packedGroups(remainder, preset: preset, style: book.style)
        var newGroups: [[Int]] = [Array(0..<newFirst)]
        for g in remainderGroups {
            newGroups.append(g.map { $0 + newFirst })
        }

        // Step 6 — build new pages, reusing old page IDs positionally.
        var master = SplitMix64(seed: seed)
        var ids = DeterministicIDGenerator(seed: master.next())
        let oldRunPages = Array(book.pages[idx..<end])

        var newRunPages: [Page] = []
        for (k, group) in newGroups.enumerated() {
            let groupPhotos = group.map { runPhotos[$0] }
            let needsTextZone = k < oldRunPages.count ? !oldRunPages[k].textSlots.isEmpty : false
            let prevPage: Page? = k == 0
                ? (idx > 0 ? book.pages[idx - 1] : nil)
                : newRunPages[k - 1]
            var newPage = makeStandardPage(photos: groupPhotos, preset: preset,
                                           style: book.style, needsTextZone: needsTextZone,
                                           seed: master.next(), previousPage: prevPage,
                                           ids: &ids)
            // Reuse the old page ID positionally when available.
            if k < oldRunPages.count {
                newPage.id = oldRunPages[k].id
                newPage.edgeStyleOverride = oldRunPages[k].edgeStyleOverride
                newPage.backgroundColorHex = oldRunPages[k].backgroundColorHex
            }
            newRunPages.append(newPage)
        }

        // Step 7 — splice.
        var result = book
        result.pages = Array(book.pages[0..<idx]) + newRunPages + Array(book.pages[end...])
        return result
    }

    // MARK: - repaginateBook

    /// Re-paginates every maximal run of reshuffleable standard, non-spread
    /// interior pages, regrouping each run's photos with the weight-consuming
    /// void-fill packer — so a raised `userWeight` lands its photo on a
    /// less-crowded page. Cover pages, locked pages/slots, and spread members
    /// bound the runs and are copied verbatim, so manual edits and spreads
    /// survive. Photo order within a run is preserved; old page IDs (and
    /// edge-style/background overrides) are reused positionally.
    public func repaginateBook(_ book: Book, preset: PrintPreset, seed: UInt64) -> Book {
        var master = SplitMix64(seed: seed)
        var ids = DeterministicIDGenerator(seed: master.next())
        let analyzedByID = analyzedLibrary(of: book)
        let pages = book.pages

        var newPages: [Page] = []
        var index = 0
        while index < pages.count {
            let page = pages[index]
            guard page.role == .standard, page.spreadID == nil, isReshuffleable(page) else {
                newPages.append(page)                     // cover / locked / spread member: pinned
                index += 1
                continue
            }
            // Extend the maximal reflowable run [index, end).
            var end = index
            while end < pages.count,
                  pages[end].role == .standard,
                  pages[end].spreadID == nil,
                  isReshuffleable(pages[end]) {
                end += 1
            }
            let runPages = Array(pages[index..<end])
            let runPhotos: [AnalyzedPhoto] = runPages.flatMap { p in
                p.photoSlots.compactMap { $0.photoID.flatMap { analyzedByID[$0] } }
            }
            guard !runPhotos.isEmpty else {
                newPages.append(contentsOf: runPages)
                index = end
                continue
            }
            var prev: Page? = newPages.last
            for (k, group) in packedGroups(runPhotos, preset: preset, style: book.style).enumerated() {
                let groupPhotos = group.map { runPhotos[$0] }
                // Text zones are positional, not content-following (same contract as repaginate): a regrouped run keeps text zones at the same page positions.
                var newPage = makeStandardPage(
                    photos: groupPhotos, preset: preset, style: book.style,
                    needsTextZone: k < runPages.count ? !runPages[k].textSlots.isEmpty : false,
                    seed: master.next(), previousPage: prev, ids: &ids,
                    pageEdgeStyle: k < runPages.count ? runPages[k].edgeStyleOverride : nil)
                if k < runPages.count {
                    newPage.id = runPages[k].id
                    // pageEdgeStyle above drives layout geometry; this persists the field.
                    newPage.edgeStyleOverride = runPages[k].edgeStyleOverride
                    newPage.backgroundColorHex = runPages[k].backgroundColorHex
                }
                newPages.append(newPage)
                prev = newPage
            }
            index = end
        }
        var result = book
        result.pages = newPages
        return result
    }

    // MARK: - layoutOptions

    /// Layout choices for the selected page grouped by photo count, high → low.
    /// Feasible counts run `1 ... min(maxPhotosPerPage, runPhotoCount)` where
    /// `runPhotoCount` is the photos available in the page's downstream
    /// reflowable run (the same run `repaginate` reflows). Each count's
    /// candidates come from the existing providers via the scoring path; the
    /// first `N` run photos drive orientation ranking. Empty for ineligible
    /// pages (non-standard, spread member, locked).
    public func layoutOptions(for pageID: UUID, in book: Book, preset: PrintPreset)
        -> [(count: Int, candidates: [LayoutCandidate])] {
        guard let idx = book.pages.firstIndex(where: { $0.id == pageID }),
              book.pages[idx].role == .standard,
              book.pages[idx].spreadID == nil,
              isReshuffleable(book.pages[idx]) else { return [] }

        // Downstream reflowable run [idx, end) — identical bound to repaginate.
        var end = idx
        while end < book.pages.count,
              book.pages[end].role == .standard,
              book.pages[end].spreadID == nil,
              isReshuffleable(book.pages[end]) {
            end += 1
        }
        let analyzedByID = analyzedLibrary(of: book)
        let runPhotos: [AnalyzedPhoto] = book.pages[idx..<end].flatMap { page in
            page.photoSlots.compactMap { slot in slot.photoID.flatMap { analyzedByID[$0] } }
        }
        let maxCount = min(Paginator.maxPhotosPerPage, runPhotos.count)
        guard maxCount >= 1 else { return [] }

        let effectiveEdgeStyle = book.pages[idx].edgeStyleOverride ?? book.style.edgeStyle
        let needsTextZone = !book.pages[idx].textSlots.isEmpty
        let previous = idx > 0 ? book.pages[idx - 1] : nil

        var result: [(count: Int, candidates: [LayoutCandidate])] = []
        var n = maxCount
        while n >= 1 {
            let firstN = Array(runPhotos.prefix(n))
            let context = LayoutContext(pageSize: preset.trimSize, style: book.style,
                                        needsTextZone: needsTextZone,
                                        seed: Self.stableSeed(for: pageID) &+ UInt64(n),
                                        edgeStyle: effectiveEdgeStyle)
            let scored = scoredCandidates(photos: firstN, context: context, previousPage: previous)
            result.append((count: n, candidates: Self.diverseOptions(scored)))
            n -= 1
        }
        return result
    }

    // MARK: - convert / revert spreads

    /// Merges the standard page `leftPageID` and its facing partner (the NEXT
    /// page) into a single first-class spread. Both must be interior standard
    /// pages, reshuffleable, and not already spread members. Their photos are
    /// gathered left-to-right and packed by `JustifiedSpreadLayout` so every
    /// slot is sized to its photo's own aspect (zero crop — the whole photo
    /// shows). The two pages are replaced by sliced member pages bound to the
    /// new spread. Ineligible input returns `book` unchanged.
    public func convertToSpread(_ book: Book, leftPageID: UUID, preset: PrintPreset,
                                seed: UInt64) -> Book {
        guard let idx = book.pages.firstIndex(where: { $0.id == leftPageID }),
              idx + 1 < book.pages.count,
              idx > 0 else { return book }   // cover (pages[0]) is never a member
        let left = book.pages[idx]
        let right = book.pages[idx + 1]
        guard left.role == .standard, right.role == .standard,
              left.spreadID == nil, right.spreadID == nil,
              isReshuffleable(left), isReshuffleable(right) else { return book }

        let analyzedByID = analyzedLibrary(of: book)
        let photos: [AnalyzedPhoto] = (left.photoSlots + right.photoSlots)
            .compactMap { $0.photoID.flatMap { analyzedByID[$0] } }
        guard !photos.isEmpty else { return book }

        var master = SplitMix64(seed: seed)
        var ids = DeterministicIDGenerator(seed: master.next())
        let (spread, members) = buildSpread(photos: photos, preset: preset,
                                            style: book.style, ids: &ids)

        var result = book
        result.pages.replaceSubrange(idx...(idx + 1), with: members)
        result.spreads.append(spread)
        return result
    }

    /// Removes the spread `spreadID` and rebuilds its two member pages as
    /// independent standard pages, laid out from their photos via the normal
    /// scoring path. The spread's photos are split across the two pages by the
    /// canvas-frame center of the slot they occupied (x < 0.5 → left page).
    /// Cleared bindings. Unknown id returns `book` unchanged.
    public func revertSpread(_ book: Book, spreadID: UUID, preset: PrintPreset,
                             seed: UInt64) -> Book {
        guard let spread = book.spreads.first(where: { $0.id == spreadID }),
              let leftIdx = book.pages.firstIndex(where: {
                  $0.spreadID == spreadID && $0.half == .left
              }),
              let rightIdx = book.pages.firstIndex(where: {
                  $0.spreadID == spreadID && $0.half == .right
              }) else { return book }

        let analyzedByID = analyzedLibrary(of: book)
        // Split the spread's photos by their slot's canvas-frame center x.
        var leftPhotos: [AnalyzedPhoto] = []
        var rightPhotos: [AnalyzedPhoto] = []
        for slot in spread.photoSlots {
            guard let photoID = slot.photoID, let photo = analyzedByID[photoID] else { continue }
            let centerX = slot.frame.x + slot.frame.width / 2
            if centerX < Spread.gutter { leftPhotos.append(photo) }
            else { rightPhotos.append(photo) }
        }

        var master = SplitMix64(seed: seed)
        var ids = DeterministicIDGenerator(seed: master.next())

        let oldLeft = book.pages[leftIdx]
        let oldRight = book.pages[rightIdx]
        let lowIdx = min(leftIdx, rightIdx)
        let beforePage = lowIdx > 0 ? book.pages[lowIdx - 1] : nil

        func rebuild(_ photos: [AnalyzedPhoto], reuseID: UUID, background: String?,
                     previous: Page?) -> Page {
            guard !photos.isEmpty else {
                // No photos on this side: an empty single full-bleed page.
                return Page(id: reuseID, role: .standard,
                            origin: .template(id: "one-full-bleed"),
                            photoSlots: [], textSlots: [], isLocked: false,
                            backgroundColorHex: background)
            }
            var page = makeStandardPage(photos: photos, preset: preset, style: book.style,
                                        needsTextZone: false, seed: master.next(),
                                        previousPage: previous, ids: &ids)
            page.id = reuseID
            page.backgroundColorHex = background  // preserve bg override across revert
            return page
        }

        let newLeft = rebuild(leftPhotos, reuseID: oldLeft.id,
                              background: oldLeft.backgroundColorHex, previous: beforePage)
        let newRight = rebuild(rightPhotos, reuseID: oldRight.id,
                               background: oldRight.backgroundColorHex, previous: newLeft)

        var result = book
        // Replace in original positional order (left member then right member).
        if leftIdx < rightIdx {
            result.pages[leftIdx] = newLeft
            result.pages[rightIdx] = newRight
        } else {
            result.pages[rightIdx] = newRight
            result.pages[leftIdx] = newLeft
        }
        result.spreads.removeAll { $0.id == spreadID }
        return result
    }

    // MARK: - placeRemaining

    /// Paginates every library photo not yet placed in any slot onto new
    /// pages appended at the (unlocked) tail. Existing pages are untouched.
    public func placeRemaining(_ book: Book, preset: PrintPreset, seed: UInt64) -> Book {
        var placed = Set<PhotoID>()
        for page in book.pages {
            for slot in page.photoSlots {
                if let photoID = slot.photoID { placed.insert(photoID) }
            }
        }
        let remaining = book.photoLibrary.filter { !placed.contains($0.id) }
        guard !remaining.isEmpty else { return book }

        var result = book
        var master = SplitMix64(seed: seed)
        var ids = DeterministicIDGenerator(seed: master.next())
        let analyzed = PhotoAnalyzer.analyze(remaining)
        var previousPage = result.pages.last
        for indices in packedGroups(analyzed, preset: preset, style: book.style) {
            let page = makeStandardPage(photos: indices.map { analyzed[$0] }, preset: preset,
                                        style: book.style, needsTextZone: false,
                                        seed: master.next(), previousPage: previousPage,
                                        ids: &ids)
            result.pages.append(page)
            previousPage = page
        }
        return result
    }

    // MARK: - Shared internals

    /// Laid-out photo coverage of `photos` on a page of `preset`/`style`, in
    /// [0,1] of the content area (margin excluded). Uses a fixed seed so the
    /// packing decision is deterministic and independent of per-page seeds.
    private func coverage(of photos: [AnalyzedPhoto], preset: PrintPreset, style: BookStyle) -> Double {
        guard !photos.isEmpty else { return 0 }
        let context = LayoutContext(pageSize: preset.trimSize, style: style,
                                    needsTextZone: false, seed: 0, edgeStyle: style.edgeStyle)
        guard let frames = scoredCandidates(photos: photos, context: context,
                                            previousPage: nil).first?.candidate.photoSlotFrames,
              !frames.isEmpty else { return 0 }
        let slotArea = frames.reduce(0.0) { $0 + $1.width * $1.height }
        let margin = style.edgeStyle.hasOuterMargin ? style.pageMargin : 0
        let content = NormRect.full.inset(by: margin)
        let contentArea = content.width * content.height
        return contentArea > 0 ? slotArea / contentArea : 0
    }

    /// Pack photos into page groups using the void-fill greedy packer.
    private func packedGroups(_ analyzed: [AnalyzedPhoto], preset: PrintPreset,
                              style: BookStyle) -> [[Int]] {
        PagePacker.pack(photos: analyzed) { pagePhotos in
            self.coverage(of: pagePhotos, preset: preset, style: style)
        }
    }

    private func analyzedLibrary(of book: Book) -> [PhotoID: AnalyzedPhoto] {
        Dictionary(uniqueKeysWithValues:
            PhotoAnalyzer.analyze(book.photoLibrary).map { ($0.id, $0) })
    }

    /// All providers' candidates, scored provider-blind, sorted best first.
    /// Sort key is (score desc, submission order asc) — a deterministic total
    /// order even when scores tie exactly.
    private func scoredCandidates(photos: [AnalyzedPhoto], context: LayoutContext,
                                  previousPage: Page?) -> [ScoredCandidate] {
        var scored: [ScoredCandidate] = []
        for provider in providers {
            for candidate in provider.candidates(forPhotoCount: photos.count,
                                                 photos: photos, context: context) {
                scored.append(ScoredCandidate(
                    candidate: candidate,
                    score: scorer.score(candidate, photos: photos,
                                        context: context, previousPage: previousPage)))
            }
        }
        return scored.enumerated()
            .sorted { a, b in
                if a.element.score != b.element.score { return a.element.score > b.element.score }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// Picks a family-diverse, de-duplicated option set for the strip: dedup by
    /// shape signature, then cap each family (justified 3, masonry 2, grid 2),
    /// preserving the incoming score order. Guarantees row + column + grid
    /// choices appear per count instead of the top-N-by-score crowding columns out.
    private static func diverseOptions(_ scored: [ScoredCandidate]) -> [LayoutCandidate] {
        let caps: [LayoutFamily: Int] = [.justified: 3, .masonry: 2, .grid: 2]
        // Dedup key includes family so that masonry/grid layouts are never dropped
        // for matching a justified layout's shape (identical-aspect photos produce
        // the same spatial boxes across providers; we still want both in the strip).
        var seen = Set<String>()
        var used: [LayoutFamily: Int] = [:]
        var out: [LayoutCandidate] = []
        for sc in scored {
            let c = sc.candidate
            let signature = "\(c.family)|\(LayoutScorer.shapeSignature(c.photoSlotFrames))"
            if seen.contains(signature) { continue }
            let cap = caps[c.family] ?? 2
            if used[c.family, default: 0] >= cap { continue }
            seen.insert(signature)
            used[c.family, default: 0] += 1
            out.append(c)
        }
        return out
    }

    private func makeStandardPage(photos: [AnalyzedPhoto], preset: PrintPreset,
                                  style: BookStyle, needsTextZone: Bool, seed: UInt64,
                                  previousPage: Page?,
                                  ids: inout DeterministicIDGenerator,
                                  pageEdgeStyle: EdgeStyle? = nil) -> Page {
        let effectiveEdgeStyle = pageEdgeStyle ?? style.edgeStyle
        let context = LayoutContext(pageSize: preset.trimSize, style: style,
                                    needsTextZone: needsTextZone, seed: seed,
                                    edgeStyle: effectiveEdgeStyle)
        let best = scoredCandidates(photos: photos, context: context,
                                    previousPage: previousPage).first?.candidate
            // Unreachable with the default providers (GenerativeProvider
            // always emits); guards a custom zero-provider engine.
            ?? LayoutCandidate(origin: .generated(GeneratedLayoutParams(seed: seed, boxes: [.full])),
                               photoSlotFrames: [.full], textSlotFrames: [])
        return makePage(from: best, photos: photos, ids: &ids)
    }

    /// ID consumption order is fixed (page, then photo slots, then text
    /// slots) — part of the byte-stability contract.
    private func makePage(from candidate: LayoutCandidate, photos: [AnalyzedPhoto],
                          ids: inout DeterministicIDGenerator) -> Page {
        let pageID = ids.next()
        var photoSlots: [PhotoSlot] = []
        for (index, frame) in candidate.photoSlotFrames.enumerated() {
            photoSlots.append(PhotoSlot(id: ids.next(), frame: frame,
                                        photoID: index < photos.count ? photos[index].id : nil,
                                        crop: .full, isLocked: false))
        }
        var textSlots: [TextSlot] = []
        for frame in candidate.textSlotFrames {
            textSlots.append(TextSlot(id: ids.next(), frame: frame,
                                      text: StyledText(string: "", fontName: "",
                                                       pointSizeFactor: 0.04,
                                                       colorHex: "#000000", alignment: .center),
                                      isLocked: false))
        }
        return Page(id: pageID, role: .standard, origin: candidate.origin,
                    photoSlots: photoSlots, textSlots: textSlots, isLocked: false)
    }

    /// First 8 UUID bytes, big-endian — a stable per-page seed for
    /// `alternatives` that survives document save/load.
    private static func stableSeed(for id: UUID) -> UInt64 {
        let bytes = id.uuid
        var seed: UInt64 = 0
        for byte in [bytes.0, bytes.1, bytes.2, bytes.3,
                     bytes.4, bytes.5, bytes.6, bytes.7] {
            seed = (seed << 8) | UInt64(byte)
        }
        return seed
    }
}
