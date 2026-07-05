import CoreGraphics
import Foundation
import PhotoBookCore
import SwiftUI
import Testing
@testable import PhotoBookRender

/// Golden-image tests for the screen renderer, run on the macOS host via
/// `ImageRenderer`. `PageSnapshotView` shares `PageLayoutView`,
/// `PhotoSlotContent`, `TextSlotContent`, and `SlotGeometry` with the public
/// `PageView`, so these goldens pin the screen layout math.
@MainActor
@Suite struct PageRenderGoldenTests {

    /// 600×600: the square preset's aspect at a fixed pixel size.
    static let renderSize = CGSize(width: 600, height: 600)

    private func render(page: Page, book: Book, images: [PhotoID: CGImage]) throws -> CGImage {
        let renderer = ImageRenderer(content: PageSnapshotView(
            page: page, book: book, renderSize: Self.renderSize, images: images))
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "ImageRenderer produced no image")
        return image
    }

    private func prefetch(_ store: SolidColorImageStore, ids: [PhotoID]) async throws -> [PhotoID: CGImage] {
        var images: [PhotoID: CGImage] = [:]
        for id in ids {
            images[id] = try await store.thumbnail(for: id, maxPixelSize: 512)
        }
        return images
    }

    // MARK: Fixtures

    private func fixtureBook(refs: [PhotoRef], pages: [Page]) -> Book {
        var book = Book(title: "Golden", presetID: "blurb-small-square", style: .standard)
        book.photoLibrary = refs
        book.pages = pages
        return book
    }

    private static let redID = PhotoID(rawValue: "golden-red")
    private static let blueID = PhotoID(rawValue: "golden-blue")
    private static let greenID = PhotoID(rawValue: "golden-green")
    private static let missingID = PhotoID(rawValue: "golden-missing")

    private func ref(_ id: PhotoID, width: Int, height: Int, isMissing: Bool = false) -> PhotoRef {
        PhotoRef(id: id, source: .file(bookmark: Data()), pixelWidth: width, pixelHeight: height,
                 isMissing: isMissing)
    }

    private var store: SolidColorImageStore {
        SolidColorImageStore(entries: [
            Self.redID: .init(red: 0.8, green: 0.1, blue: 0.1, pixelWidth: 800, pixelHeight: 600),
            Self.blueID: .init(red: 0.1, green: 0.2, blue: 0.8, pixelWidth: 600, pixelHeight: 800),
            Self.greenID: .init(red: 0.1, green: 0.7, blue: 0.2, pixelWidth: 640, pixelHeight: 640)
        ])
    }

    // MARK: Tests

    @Test func twoPhotoTemplatePage() async throws {
        let page = Page(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            origin: .template(id: "two-up"),
            photoSlots: [
                PhotoSlot(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
                          frame: NormRect(x: 0.05, y: 0.05, width: 0.425, height: 0.9),
                          photoID: Self.redID),
                PhotoSlot(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
                          frame: NormRect(x: 0.525, y: 0.05, width: 0.425, height: 0.9),
                          photoID: Self.blueID)
            ])
        let book = fixtureBook(
            refs: [ref(Self.redID, width: 800, height: 600), ref(Self.blueID, width: 600, height: 800)],
            pages: [page])
        let images = try await prefetch(store, ids: [Self.redID, Self.blueID])
        let rendered = try render(page: page, book: book, images: images)
        try GoldenImage.assertMatchesGolden(rendered, named: "page-two-photo-template")
    }

    @Test func pageWithTextSlot() async throws {
        let page = Page(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
            origin: .template(id: "hero-caption"),
            photoSlots: [
                PhotoSlot(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!,
                          frame: NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.6),
                          photoID: Self.greenID)
            ],
            textSlots: [
                TextSlot(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
                         frame: NormRect(x: 0.1, y: 0.75, width: 0.8, height: 0.15),
                         text: StyledText(string: "Summer 2025", fontName: "",
                                          pointSizeFactor: 0.05, colorHex: "#222222",
                                          alignment: .center))
            ])
        let book = fixtureBook(refs: [ref(Self.greenID, width: 640, height: 640)], pages: [page])
        let images = try await prefetch(store, ids: [Self.greenID])
        let rendered = try render(page: page, book: book, images: images)
        try GoldenImage.assertMatchesGolden(rendered, named: "page-text-slot")
    }

    @Test func pageWithMissingPhoto() async throws {
        let page = Page(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!,
            origin: .template(id: "two-up"),
            photoSlots: [
                PhotoSlot(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!,
                          frame: NormRect(x: 0.05, y: 0.05, width: 0.425, height: 0.9),
                          photoID: Self.greenID),
                PhotoSlot(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B5")!,
                          frame: NormRect(x: 0.525, y: 0.05, width: 0.425, height: 0.9),
                          photoID: Self.missingID)
            ])
        let book = fixtureBook(
            refs: [ref(Self.greenID, width: 640, height: 640),
                   ref(Self.missingID, width: 800, height: 600, isMissing: true)],
            pages: [page])
        let images = try await prefetch(store, ids: [Self.greenID])
        let rendered = try render(page: page, book: book, images: images)
        try GoldenImage.assertMatchesGolden(rendered, named: "page-missing-photo")
    }
}
