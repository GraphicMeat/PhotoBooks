import CoreGraphics
import Foundation
import PhotoBookCore
import SwiftUI
import Testing
@testable import PhotoBookRender

@Suite struct BackgroundColorRenderTests {

    // MARK: Resolver contract

    @Test func pageLayoutUsesEffectiveColorNotBookStyle() {
        let style = BookStyle.standard                 // book default #FFFFFF
        let page = Page(origin: .template(id: "x"), backgroundColorHex: "#FF0000")
        // The renderer must paint the page override, not the book default.
        #expect(page.effectiveBackgroundHex(bookDefault: style.backgroundColorHex) == "#FF0000")
    }

    @Test func pageWithNoOverrideInheritsBookDefault() {
        let style = BookStyle.standard                 // #FFFFFF
        let page = Page(origin: .template(id: "x"))   // no override
        #expect(page.effectiveBackgroundHex(bookDefault: style.backgroundColorHex) == "#FFFFFF")
    }

    // MARK: Pixel-level render test (synchronous snapshot path)

    /// Renders a page whose `backgroundColorHex` is overridden to pure red
    /// and samples the top-left background pixel.  The pixel must be red —
    /// not the book default white — proving `PageLayoutView` uses the
    /// per-page effective color rather than `style.backgroundColorHex` directly.
    @MainActor
    @Test func snapshotPaintsPageOverrideColor() throws {
        let renderSize = CGSize(width: 100, height: 100)
        let page = Page(origin: .template(id: "bg-test"), backgroundColorHex: "#FF0000")
        var book = Book(title: "BgTest", presetID: "blurb-small-square", style: .standard)
        book.pages = [page]

        let renderer = ImageRenderer(content: PageSnapshotView(
            page: page, book: book, renderSize: renderSize, images: [:]))
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "ImageRenderer produced no image")

        // Sample the centre pixel (50, 50) — should be solid red.
        let pixels = GoldenImage.rgbaPixels(of: image)
        let cx = 50, cy = 50
        let offset = (cy * image.width + cx) * 4
        let r = Int(pixels[offset])
        let g = Int(pixels[offset + 1])
        let b = Int(pixels[offset + 2])

        // Red channel ≥ 200, green+blue ≤ 30.
        #expect(r >= 200, "Expected red background pixel; got r=\(r) g=\(g) b=\(b)")
        #expect(g <= 30,  "Expected red background pixel; got r=\(r) g=\(g) b=\(b)")
        #expect(b <= 30,  "Expected red background pixel; got r=\(r) g=\(g) b=\(b)")
    }
}
