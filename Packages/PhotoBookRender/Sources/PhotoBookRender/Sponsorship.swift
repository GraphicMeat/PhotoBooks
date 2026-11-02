import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// The sponsor page a free export carries: "sponsored by" MailVault, made by
/// Graphic Meat. Fixed dark artwork, whatever the book's style, because half of
/// the MailVault wordmark is white and would vanish on a light page.
public struct Sponsorship: @unchecked Sendable {   // CGImages are immutable
    /// Interior pages a sponsored print export adds: a sponsor page and its
    /// blank facing page, at each end of the book.
    public static let printedPageCount = 4

    public static let standard = Sponsorship()

    private static let sponsorURL = URL(string: "https://mailvaultapp.com")!
    private static let makerURL = URL(string: "https://graphicmeat.com")!

    private let mailVaultIcon = loadImage(named: "SponsorMailVaultIcon")
    private let mailVaultWordmark = loadImage(named: "SponsorMailVaultWordmark")
    private let makerLogo = loadImage(named: "SponsorMakerLogo")

    private init() {}

    private static func loadImage(named name: String) -> CGImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            fatalError("Missing bundled sponsor artwork \(name).png")
        }
        return image
    }

    /// Fills the whole media box, bleed included, then stacks the content down
    /// the centre of `contentRect` (top-left-origin, like every export rect).
    /// Returns the clickable areas, in the context's own coordinates.
    @discardableResult
    func draw(in context: CGContext, mediaSize: CGSize, contentRect: CGRect,
              maxDPI: Double) -> [(url: URL, rect: CGRect)] {
        context.setFillColor(CGColor(srgbRed: 0.055, green: 0.059, blue: 0.078, alpha: 1))
        context.fill(CGRect(origin: .zero, size: mediaSize))

        let unit = min(contentRect.width, contentRect.height)
        let midX = contentRect.midX
        let mainWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let quietWhite = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.72)
        let sponsoredBy = String(localized: "This album is sponsored by", bundle: .module)
        let made = String(localized: "Made", bundle: .module)

        func height(of image: CGImage, width: CGFloat) -> CGFloat {
            width * CGFloat(image.height) / CGFloat(image.width)
        }
        let iconSide = unit * 0.30
        let wordmarkWidth = unit * 0.44, wordmarkHeight = height(of: mailVaultWordmark, width: wordmarkWidth)
        let logoWidth = unit * 0.46, logoHeight = height(of: makerLogo, width: logoWidth)
        let captionSize = unit * 0.028, urlSize = unit * 0.03, madeSize = unit * 0.024
        let stack = captionSize + unit * 0.05 + iconSide + unit * 0.04 + wordmarkHeight
            + unit * 0.03 + urlSize + unit * 0.14 + madeSize + unit * 0.02 + logoHeight

        // Walks down the page from the top of the centred stack.
        var top = mediaSize.height - contentRect.midY + stack / 2

        func place(_ image: CGImage, width: CGFloat, height: CGFloat) -> CGRect {
            let rect = CGRect(x: midX - width / 2, y: top - height, width: width, height: height)
            let budget = PDFDownsampler.maxPixelSize(drawnPointSize: rect.size, maxDPI: maxDPI)
            context.draw(PDFDownsampler.downsample(image, maxPixelSize: budget), in: rect)
            top -= height
            return rect
        }
        func write(_ text: String, size: CGFloat, bold: Bool = false, color: CGColor) -> CGRect {
            let rect = drawLine(text, size: size, bold: bold, color: color,
                                centeredAt: midX, top: top, in: context)
            top -= size
            return rect
        }

        _ = write(sponsoredBy, size: captionSize, color: quietWhite)
        top -= unit * 0.05
        let icon = place(mailVaultIcon, width: iconSide, height: iconSide)
        top -= unit * 0.04
        let wordmark = place(mailVaultWordmark, width: wordmarkWidth, height: wordmarkHeight)
        top -= unit * 0.03
        let address = write("mailvaultapp.com", size: urlSize, bold: true, color: mainWhite)
        top -= unit * 0.14
        _ = write(made, size: madeSize, color: quietWhite)
        top -= unit * 0.02
        let maker = place(makerLogo, width: logoWidth, height: logoHeight)

        return [(Self.sponsorURL, icon.union(wordmark).union(address)), (Self.makerURL, maker)]
    }

    private func drawLine(_ text: String, size: CGFloat, bold: Bool, color: CGColor,
                          centeredAt midX: CGFloat, top: CGFloat, in context: CGContext) -> CGRect {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as CFDictionary
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attributes))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: midX - width / 2, y: top - size * 0.8)
        CTLineDraw(line, context)
        context.restoreGState()
        return CGRect(x: midX - width / 2, y: top - size, width: width, height: size)
    }
}
