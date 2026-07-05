import CoreText
import Foundation
import PhotoBookCore
import Testing
@testable import PhotoBookRender

@Suite struct PDFTextTests {

    @Test func fontResolutionAndSize() {
        // "" defers to the style default; size = factor × renderHeight.
        let styled = StyledText(string: "Hi", fontName: "", pointSizeFactor: 0.05,
                                colorHex: "#000000", alignment: .center)
        let attributed = PDFText.attributedString(for: styled, style: .standard,
                                                  renderHeight: 504)
        let font = attributed.attribute(NSAttributedString.Key(kCTFontAttributeName as String),
                                        at: 0, effectiveRange: nil)
        let ctFont = font as! CTFont
        #expect(abs(CTFontGetSize(ctFont) - 25.2) < 1e-9)        // 0.05 × 504
        #expect(CTFontCopyPostScriptName(ctFont) as String == "HelveticaNeue")

        // Unknown PostScript names substitute (never nil) at the same size.
        let unknown = StyledText(string: "Hi", fontName: "NoSuchFont-Bold",
                                 pointSizeFactor: 0.05, colorHex: "#000000",
                                 alignment: .center)
        let attributed2 = PDFText.attributedString(for: unknown, style: .standard,
                                                   renderHeight: 504)
        let ctFont2 = attributed2.attribute(NSAttributedString.Key(kCTFontAttributeName as String),
                                            at: 0, effectiveRange: nil) as! CTFont
        #expect(abs(CTFontGetSize(ctFont2) - 25.2) < 1e-9)
    }
}
