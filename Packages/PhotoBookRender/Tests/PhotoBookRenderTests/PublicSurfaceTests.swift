import CoreGraphics
import Foundation
import PhotoBookCore
import SwiftUI
import Testing
import PhotoBookRender   // plain import: pins the PUBLIC surface

/// Compile-level contract check: the public initializers exist with the
/// pinned signatures, and a `PageView`/`SpreadView` can be constructed and
/// laid out by `ImageRenderer` without crashing (async slots render their
/// placeholder state — pixel content is covered by the golden tests).
@MainActor
@Suite struct PublicSurfaceTests {

    private func sampleBook() -> (Book, Page, PrintPreset) {
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        let id = PhotoID(rawValue: "p1")
        let page = Page(origin: .template(id: "single"),
                        photoSlots: [PhotoSlot(frame: NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                                               photoID: id)])
        var book = Book(title: "T", presetID: preset.id, style: .standard)
        book.photoLibrary = [PhotoRef(id: id, source: .file(bookmark: Data()),
                                      pixelWidth: 800, pixelHeight: 600)]
        book.pages = [page]
        return (book, page, preset)
    }

    private var emptyStore: SolidColorImageStore { SolidColorImageStore(entries: [:]) }

    @Test func pageViewRendersAtPresetAspect() throws {
        let (book, page, preset) = sampleBook()
        let view = PageView(page: page, book: book, preset: preset, imageStore: emptyStore,
                            highlightedSlotID: nil)
            .frame(width: 300, height: 300)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 300)
        #expect(image.height == 300)
    }

    @Test func spreadViewAcceptsNilPages() throws {
        let (book, page, preset) = sampleBook()
        let view = SpreadView(leftPage: nil, rightPage: page, book: book, preset: preset,
                              imageStore: emptyStore)
            .frame(width: 620, height: 300)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        #expect(image.width == 620)
    }
}
