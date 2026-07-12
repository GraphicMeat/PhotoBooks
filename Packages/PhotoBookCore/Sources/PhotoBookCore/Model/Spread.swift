import Foundation

/// Which physical page a sliced spread half lands on. The spread is authored
/// on a double-wide canvas (x ∈ 0…1 spans BOTH facing pages, gutter at x=0.5);
/// `slice()` projects it onto two real pages, each in its own 0–1 space.
public enum SpreadHalf: String, Codable, Hashable, Sendable {
    case left, right
}

/// A photo placement on the double-wide spread canvas. `frame` is canvas space
/// (x ∈ 0…1 across both pages); `crop` is a sub-rect of the SOURCE photo
/// (default full). Sliced by `Spread.slice()` into per-page `PhotoSlot`s.
public struct SpreadPhotoSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var frame: NormRect      // double-wide canvas space
    public var photoID: PhotoID?
    public var crop: NormRect       // source-photo sub-rect; default .full

    public init(id: UUID = UUID(), frame: NormRect, photoID: PhotoID? = nil, crop: NormRect = .full) {
        self.id = id
        self.frame = frame
        self.photoID = photoID
        self.crop = crop
    }
}

/// A text zone on the spread canvas. Routed by `slice()` to whichever half
/// contains its frame center.
public struct SpreadTextSlot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var frame: NormRect      // canvas space
    public var text: StyledText

    public init(id: UUID = UUID(), frame: NormRect, text: StyledText) {
        self.id = id
        self.frame = frame
        self.text = text
    }
}

/// One physical page's worth of sliced slots — the bridge back to the existing
/// per-page render/export pipeline (which consumes `PhotoSlot`/`TextSlot`).
public struct SlicedHalf: Equatable, Sendable {
    public var photoSlots: [PhotoSlot]
    public var textSlots: [TextSlot]

    public init(photoSlots: [PhotoSlot] = [], textSlots: [TextSlot] = []) {
        self.photoSlots = photoSlots
        self.textSlots = textSlots
    }
}

/// A first-class 2-page spread authored on a double-wide canvas. The gutter is
/// at canvas x = 0.5; the left page is x∈[0,0.5], the right page x∈[0.5,1].
/// `slice()` projects the canvas onto the two real pages so the existing
/// per-page pipeline is unchanged.
public struct Spread: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var origin: LayoutOrigin            // template(id) | generated(...)
    public var photoSlots: [SpreadPhotoSlot]
    public var textSlots: [SpreadTextSlot]

    public init(id: UUID = UUID(), origin: LayoutOrigin,
                photoSlots: [SpreadPhotoSlot], textSlots: [SpreadTextSlot] = []) {
        self.id = id
        self.origin = origin
        self.photoSlots = photoSlots
        self.textSlots = textSlots
    }

    /// The gutter position in canvas x. Left page = [0, gutter], right = [gutter, 1].
    static let gutter = 0.5

    /// Projects the double-wide canvas onto the two real pages. A photo slot
    /// straddling the gutter slices into complementary half-crops; a slot
    /// wholly on one side maps to that page with its full crop. Text slots go
    /// to whichever half contains their frame center.
    ///
    /// Sliced-slot ids are derived deterministically from `id` (a
    /// `DeterministicIDGenerator` seeded by the spread id, consumed in a fixed
    /// order: for each photo slot left-then-right, then each text slot's
    /// chosen side) so re-slicing the same spread is byte-identical.
    public func slice() -> (left: SlicedHalf, right: SlicedHalf) {
        var ids = DeterministicIDGenerator(seed: Self.stableSeed(for: id))
        var left = SlicedHalf()
        var right = SlicedHalf()

        let g = Self.gutter
        for slot in photoSlots {
            let fx = slot.frame.x, fy = slot.frame.y
            let fw = slot.frame.width, fh = slot.frame.height
            let cx = slot.crop.x, cy = slot.crop.y
            let cw = slot.crop.width, ch = slot.crop.height

            let straddles = fx < g - 1e-12 && fx + fw > g + 1e-12

            // LEFT intersection = frame ∩ [x:0, w:0.5] — non-empty when fx < g.
            // ID is consumed FIRST (left) for every photo slot — even when the
            // left intersection is empty — so the consumption order is fixed.
            let leftID = ids.next()
            if fx < g - 1e-12 {
                let leftMaxX = min(fx + fw, g)
                let frame = NormRect(x: fx / g, y: fy,
                                     width: (leftMaxX - fx) / g, height: fh)
                // Wholly-left slots keep the full crop exactly (no float drift);
                // straddling slots take the left fraction of the crop width.
                let crop: NormRect = straddles
                    ? NormRect(x: cx, y: cy, width: cw * ((leftMaxX - fx) / fw), height: ch)
                    : slot.crop
                left.photoSlots.append(PhotoSlot(id: leftID, frame: frame,
                                                 photoID: slot.photoID, crop: crop))
            }

            // RIGHT intersection = frame ∩ [x:0.5, w:0.5] — non-empty when fx+fw > g.
            let rightID = ids.next()
            if fx + fw > g + 1e-12 {
                let rightMinX = max(fx, g)
                let frame = NormRect(x: (rightMinX - g) / g, y: fy,
                                     width: (fx + fw - rightMinX) / g, height: fh)
                let crop: NormRect
                if straddles {
                    let rfrac = (fx + fw - rightMinX) / fw
                    crop = NormRect(x: cx + cw * (1 - rfrac), y: cy,
                                    width: cw * rfrac, height: ch)
                } else {
                    crop = slot.crop
                }
                right.photoSlots.append(PhotoSlot(id: rightID, frame: frame,
                                                  photoID: slot.photoID, crop: crop))
            }
        }

        for slot in textSlots {
            let textID = ids.next()
            let centerX = slot.frame.x + slot.frame.width / 2
            let styled = TextSlot(id: textID, frame: NormRect(), text: slot.text)
            if centerX < g {
                var sliced = styled
                sliced.frame = NormRect(x: slot.frame.x / g, y: slot.frame.y,
                                        width: slot.frame.width / g, height: slot.frame.height)
                left.textSlots.append(sliced)
            } else {
                var sliced = styled
                sliced.frame = NormRect(x: (slot.frame.x - g) / g, y: slot.frame.y,
                                        width: slot.frame.width / g, height: slot.frame.height)
                right.textSlots.append(sliced)
            }
        }

        return (left, right)
    }

    /// Deterministic generator for a spread's OWN photo-slot ids (the
    /// double-wide canvas slots — distinct from the sliced-page ids `slice()`
    /// derives from `stableSeed` unsalted). Single source of truth for
    /// `BookEngine.buildSpread` AND `BookEngine.applySpreadTemplate`: same
    /// spread id ⇒ same slot ids, which is what makes re-applying a template
    /// to an existing spread byte-stable.
    static func slotIDGenerator(for id: UUID) -> DeterministicIDGenerator {
        DeterministicIDGenerator(seed: stableSeed(for: id) &+ 0x5170A11)
    }

    /// First 8 UUID bytes, big-endian — a stable per-spread seed so sliced
    /// slot ids survive save/load (mirrors `BookEngine.stableSeed(for:)`).
    static func stableSeed(for id: UUID) -> UInt64 {
        let bytes = id.uuid
        var seed: UInt64 = 0
        for byte in [bytes.0, bytes.1, bytes.2, bytes.3,
                     bytes.4, bytes.5, bytes.6, bytes.7] {
            seed = (seed << 8) | UInt64(byte)
        }
        return seed
    }
}

private extension NormRect {
    init() { self.init(x: 0, y: 0, width: 0, height: 0) }
}
