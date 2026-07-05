import CoreGraphics
import Foundation
import PhotoBookCore

/// Print-resolution downsampling (D3): the exporter never embeds more pixels
/// than the placement can use. Input is the already-decoded `CGImage` from
/// `ImageStore`, so downsampling is a CGContext redraw (which also converts
/// to sRGB in the same pass) rather than a CGImageSource round-trip through
/// re-encoded data.
enum PDFDownsampler {

    /// Pixel budget for an image drawn at `drawnPointSize` (PDF points,
    /// 72/inch) embedded at up to `maxDPI`:
    ///     longest drawn side in inches × maxDPI, rounded UP.
    /// Worked: a 3.5 × 3.5 in placement (252 × 252 pt) at 300 DPI →
    /// ceil(3.5 × 300) = 1050 px.
    static func maxPixelSize(drawnPointSize: CGSize, maxDPI: Double) -> Int {
        let longestInches = max(drawnPointSize.width, drawnPointSize.height) / PDFExporter.pointsPerInch
        let target = longestInches * maxDPI
        guard target.isFinite, target >= 1 else { return 1 }
        return Int(target.rounded(.up))
    }

    /// Scales `image` down so its longest side is at most `maxPixelSize`.
    /// Never upsamples; output is tagged sRGB. Falls back to the original
    /// image if a context cannot be made (never fails the export over it).
    static func downsample(_ image: CGImage, maxPixelSize: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixelSize, maxPixelSize >= 1 else { return image }
        let scale = Double(maxPixelSize) / Double(longest)
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

/// Draws one `Page` into any `CGContext` using the SAME `SlotGeometry`
/// functions as the screen renderer (shared invariant 3): one global flip to
/// top-left-origin coordinates, then every rect is exactly what `PageView`
/// computes. Works against bitmap contexts too — the pixel-probe tests use
/// that to verify orientation without parsing PDF content streams.
struct PDFPageRenderer {

    let style: BookStyle
    let refsByID: [PhotoID: PhotoRef]
    let maxDPI: Double

    init(book: Book, maxDPI: Double) {
        self.style = book.style
        self.refsByID = Dictionary(book.photoLibrary.map { ($0.id, $0) },
                                   uniquingKeysWith: { first, _ in first })
        self.maxDPI = maxDPI
    }

    /// Fills the WHOLE media box with the page background (bleed strips carry
    /// background — D1), then maps the page's normalized space onto
    /// `contentRect` (top-left-origin points; the trim rect for bleed
    /// targets). Photos stream one at a time: fetch → downsample → draw →
    /// release (the local `image` goes out of scope every iteration).
    /// `backgroundFillRect` bounds the background fill. `nil` (default) fills
    /// the whole media box — the original behavior, so every existing caller is
    /// byte-identical. The cover sheet passes the back panel here so drawing the
    /// back cover does not repaint (and erase) the already-drawn front panel.
    func draw(page: Page, in context: CGContext, mediaSize: CGSize,
              contentRect: CGRect, imageStore: any ImageStore,
              backgroundFillRect: CGRect? = nil) async throws {
        let bg = ColorHex.components(page.effectiveBackgroundHex(bookDefault: style.backgroundColorHex))
        context.setFillColor(CGColor(srgbRed: bg.red, green: bg.green, blue: bg.blue, alpha: 1))
        context.fill(backgroundFillRect ?? CGRect(origin: .zero, size: mediaSize))

        context.saveGState()
        // The one global flip (D4): after this, top-left-origin coordinates —
        // SlotGeometry's convention — land exactly where PageView puts them.
        context.translateBy(x: 0, y: mediaSize.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: contentRect.minX, y: contentRect.minY)
        defer { context.restoreGState() }

        let renderSize = contentRect.size
        let radius = SlotGeometry.cornerRadius(style: style, in: renderSize)

        for slot in page.photoSlots {
            let slotRect = SlotGeometry.rect(for: slot.frame, in: renderSize)
            guard let photoID = slot.photoID else {
                // Empty slot: the screen shows a light gray well; WYSIWYG.
                fill(slotRect, white: 0.85, radius: radius, in: context)
                continue
            }
            // Preflight blocks missing photos before any rendering (D8);
            // reaching here with one is a programmer error upstream, but
            // never draw garbage into a print file — draw the gray well.
            guard let ref = refsByID[photoID], !ref.isMissing else {
                fill(slotRect, white: 0.8, radius: radius, in: context)
                continue
            }
            let full = try await imageStore.fullImage(for: photoID)
            let drawRect = SlotGeometry.imageDrawRect(
                slotRect: slotRect, crop: slot.crop,
                pixelWidth: full.width, pixelHeight: full.height)
            let budget = PDFDownsampler.maxPixelSize(drawnPointSize: drawRect.size,
                                                     maxDPI: maxDPI)
            let image = PDFDownsampler.downsample(full, maxPixelSize: budget)

            context.saveGState()
            context.addPath(CGPath(roundedRect: slotRect, cornerWidth: radius,
                                   cornerHeight: radius, transform: nil))
            context.clip()
            // Local counter-flip around drawRect (D4): CGContext.draw renders
            // bottom-up; y → (minY + maxY) − y maps drawRect onto itself with
            // the image upright.
            context.translateBy(x: 0, y: drawRect.minY + drawRect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(image, in: drawRect)
            context.restoreGState()
        }

        for slot in page.textSlots {
            let slotRect = SlotGeometry.rect(for: slot.frame, in: renderSize)
            PDFText.draw(slot.text, style: style, slotRect: slotRect,
                         renderHeight: renderSize.height, in: context)
        }
    }

    private func fill(_ rect: CGRect, white: CGFloat, radius: Double, in context: CGContext) {
        context.saveGState()
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius,
                               cornerHeight: radius, transform: nil))
        context.clip()
        context.setFillColor(CGColor(srgbRed: white, green: white, blue: white, alpha: 1))
        context.fill(rect)
        context.restoreGState()
    }
}
