import CoreGraphics
import Foundation
import PhotoBookCore

/// One pre-export finding. Pinned by the API contract.
public struct PreflightIssue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case missingPhoto(PhotoID)
        case lowResolution(PhotoID, effectiveDPI: Int)   // warn < 200
        case pageCountOutOfRange(actual: Int, min: Int, max: Int)
        case textOverflow(pageID: UUID)
    }
    public var kind: Kind
    public var pageIndex: Int?
    public var isBlocking: Bool          // missingPhoto blocks; others warn
}

/// Pre-export checks (spec "Export" → Preflight). Pure function of the
/// model: no image decoding — pixel dimensions come from `PhotoRef`, text
/// metrics from Core Text font data. Issue order is deterministic: the
/// book-level page-count issue first, then per-page issues in page order
/// (photo-slot issues in slot storage order, text overflow after them).
public enum Preflight {

    /// Warn when a placement renders below this effective DPI.
    static let minimumDPI = 200

    public static func check(_ book: Book, preset: PrintPreset) -> [PreflightIssue] {
        var issues: [PreflightIssue] = []

        // Page count counts STANDARD pages only — the cover is a separate
        // physical product (its own sheet for Blurb) and never counts
        // toward the interior page limits.
        let standardCount = book.pages.count(where: { $0.role == .standard })
        if standardCount < preset.minPages || standardCount > preset.maxPages {
            issues.append(PreflightIssue(
                kind: .pageCountOutOfRange(actual: standardCount,
                                           min: preset.minPages, max: preset.maxPages),
                pageIndex: nil,
                isBlocking: false))
        }

        let refsByID = Dictionary(uniqueKeysWithValues: book.photoLibrary.map { ($0.id, $0) })

        for (pageIndex, page) in book.pages.enumerated() {
            checkPage(page, pageIndex: pageIndex, refsByID: refsByID,
                      preset: preset, style: book.style, into: &issues)
        }

        // The back cover is a photo-bearing surface stored OUTSIDE `pages[]`
        // (Book.backCover). Its slots need the SAME checks or a missing /
        // dangling / low-res cover photo would silently print a gray well.
        // It isn't a page, so its issues carry `pageIndex == nil` (the same
        // sentinel book-level issues use).
        if let backCover = book.backCover {
            checkPage(backCover, pageIndex: nil, refsByID: refsByID,
                      preset: preset, style: book.style, into: &issues)
        }
        return issues
    }

    /// Runs the per-slot photo checks (missing / dangling / low-DPI) and the
    /// text-overflow check for one page-like surface, recording issues with
    /// the given `pageIndex` (`nil` for surfaces not in `book.pages[]`, such
    /// as the back cover).
    private static func checkPage(_ page: Page, pageIndex: Int?,
                                  refsByID: [PhotoID: PhotoRef], preset: PrintPreset,
                                  style: BookStyle, into issues: inout [PreflightIssue]) {
        var reportedMissing: Set<PhotoID> = []
        for slot in page.photoSlots {
            guard let photoID = slot.photoID else { continue }   // empty slot: fine
            guard refsByID[photoID] != nil, refsByID[photoID]?.isMissing == false else {
                // Dangling ID (no library entry) or explicit missing
                // state: the renderer would draw a placeholder, so
                // export blocks. One issue per (page, photo).
                if reportedMissing.insert(photoID).inserted {
                    issues.append(PreflightIssue(kind: .missingPhoto(photoID),
                                                 pageIndex: pageIndex,
                                                 isBlocking: true))
                }
                continue
            }
            let ref = refsByID[photoID]!
            if let dpi = effectiveDPI(ref: ref, slot: slot, trimSize: preset.trimSize),
               dpi < minimumDPI {
                issues.append(PreflightIssue(
                    kind: .lowResolution(photoID, effectiveDPI: dpi),
                    pageIndex: pageIndex,
                    isBlocking: false))
            }
        }
        for slot in page.textSlots where textOverflows(slot, trimSize: preset.trimSize,
                                                       style: style) {
            issues.append(PreflightIssue(kind: .textOverflow(pageID: page.id),
                                         pageIndex: pageIndex,
                                         isBlocking: false))
        }
    }

    /// A text slot overflows when Core Text needs more height than the
    /// slot frame provides at trim size: the slot frame is mapped to
    /// trim-size points via `SlotGeometry.rect`, the SAME attributed
    /// string the PDF renderer draws is measured with
    /// `CTFramesetterSuggestFrameSizeWithConstraints` at the frame's
    /// width, and the suggested height is compared against the frame
    /// height. Half a point of tolerance absorbs Core Text's
    /// ceil-to-pixel rounding so a perfectly fitting line is not flagged.
    static func textOverflows(_ slot: TextSlot, trimSize: SizeInches, style: BookStyle) -> Bool {
        guard !slot.text.string.isEmpty else { return false }
        let trimPoints = CGSize(width: trimSize.width * PDFExporter.pointsPerInch, height: trimSize.height * PDFExporter.pointsPerInch)
        let frame = SlotGeometry.rect(for: slot.frame, in: trimPoints)
        guard frame.width > 0, frame.height > 0 else { return false }
        let attributed = PDFText.attributedString(for: slot.text, style: style,
                                                  renderHeight: trimPoints.height)
        let suggested = PDFText.suggestedHeight(of: attributed,
                                                constrainedToWidth: frame.width)
        return suggested > frame.height + 0.5
    }

    /// Effective DPI of a placement:
    ///
    ///     croppedPixelsW = ref.pixelWidth  × crop.width
    ///     croppedPixelsH = ref.pixelHeight × crop.height
    ///     placedInchesW  = slot.frame.width  × trim.width
    ///     placedInchesH  = slot.frame.height × trim.height
    ///     DPI            = min(croppedPixelsW / placedInchesW,
    ///                          croppedPixelsH / placedInchesH)
    ///
    /// rounded DOWN to an Int (never overstate quality — D9). Worked:
    /// 4000×3000 full-crop in a 0.5×0.5 slot on 10×8 in → placed 5×4 in →
    /// min(800, 750) = 750. `nil` for degenerate geometry (zero-area crop
    /// or frame), which is a layout bug, not a resolution problem.
    static func effectiveDPI(ref: PhotoRef, slot: PhotoSlot, trimSize: SizeInches) -> Int? {
        let croppedPixelsW = Double(ref.pixelWidth) * slot.crop.width
        let croppedPixelsH = Double(ref.pixelHeight) * slot.crop.height
        let placedInchesW = slot.frame.width * trimSize.width
        let placedInchesH = slot.frame.height * trimSize.height
        guard croppedPixelsW > 0, croppedPixelsH > 0,
              placedInchesW > 0, placedInchesH > 0 else { return nil }
        let dpi = min(croppedPixelsW / placedInchesW, croppedPixelsH / placedInchesH)
        return Int(dpi.rounded(.down))
    }
}
