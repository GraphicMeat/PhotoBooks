import CoreGraphics
import CoreText
import Foundation
import PhotoBookCore

/// Shared Core Text plumbing for the PDF half: ONE attributed-string
/// builder used by both `Preflight.textOverflows` and `PDFPageRenderer`,
/// so the overflow check measures exactly what export draws (D5).
enum PDFText {

    /// `StyledText` → Core Text attributed string at a concrete render
    /// height. Font: PostScript name; `""` falls back to the style's
    /// default font; an unresolvable name falls back via CTFont's
    /// substitution (CTFontCreateWithName never fails). Size:
    /// `pointSizeFactor × renderHeight` via `SlotGeometry.fontPoints` —
    /// `renderHeight` is the page's render height in points (trim height
    /// × 72 for print), the same convention the screen renderer uses.
    static func attributedString(for text: StyledText, style: BookStyle,
                                 renderHeight: Double) -> NSAttributedString {
        let size = SlotGeometry.fontPoints(factor: text.pointSizeFactor,
                                           renderHeight: renderHeight)
        let name = text.fontName.isEmpty ? style.defaultFontName : text.fontName
        let font = CTFontCreateWithName(name as CFString, size, nil)

        let c = ColorHex.components(text.colorHex)
        let color = CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)

        var alignment: CTTextAlignment = switch text.alignment {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
        let paragraphStyle = withUnsafeMutableBytes(of: &alignment) { raw in
            var setting = CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: raw.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }

        return NSAttributedString(string: text.string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle,
        ])
    }

    /// Height Core Text needs to lay the whole string out at `width`.
    static func suggestedHeight(of attributed: NSAttributedString,
                                constrainedToWidth width: Double) -> Double {
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter,
            CFRange(location: 0, length: 0),
            nil,
            CGSize(width: width, height: .greatestFiniteMagnitude),
            nil)
        return size.height
    }

    /// Draws `text` into `slotRect` (TOP-LEFT-origin coordinates — the caller
    /// has already applied the page's global flip, D4). Steps: build the SAME
    /// attributed string the overflow check measures, measure it, offset the
    /// frame origin down by half the spare height (vertical centering — D5,
    /// matching `TextSlotContent`'s centered frame) and set its height to
    /// exactly `suggested` so the frame is tightly sized to the text, clip to
    /// the slot, then counter-flip locally around the frame rect because Core
    /// Text draws in bottom-left-origin coordinates, and `CTFrameDraw`.
    static func draw(_ text: StyledText, style: BookStyle, slotRect: CGRect,
                     renderHeight: Double, in context: CGContext) {
        guard !text.string.isEmpty, slotRect.width > 0, slotRect.height > 0 else { return }
        let attributed = attributedString(for: text, style: style, renderHeight: renderHeight)
        let suggested = suggestedHeight(of: attributed, constrainedToWidth: slotRect.width)
        let spare = max(0, slotRect.height - suggested)
        let frameRect = CGRect(x: slotRect.minX, y: slotRect.minY + spare / 2,
                               width: slotRect.width, height: slotRect.height - spare)

        context.saveGState()
        context.clip(to: slotRect)
        // Local counter-flip: y → (minY + maxY) − y maps frameRect onto
        // itself with the y-axis pointing up, which is what Core Text needs.
        context.translateBy(x: 0, y: frameRect.minY + frameRect.maxY)
        context.scaleBy(x: 1, y: -1)
        let path = CGPath(rect: frameRect, transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        context.textMatrix = .identity
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}
