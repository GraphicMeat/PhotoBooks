import CoreGraphics
import Foundation
import PhotoBookCore
import SwiftUI
import Testing
@testable import PhotoBookRender

@MainActor
@Suite struct PageEditingTests {

    // MARK: Render helpers

    /// Renders a view at 1x and returns its pixels redrawn into a known
    /// RGBA8 layout, so byte comparison and sampling are format-stable.
    private func rgbaPixels(of view: some View, width: Int, height: Int) throws -> Data {
        let renderer = ImageRenderer(content: AnyView(view.frame(width: CGFloat(width),
                                                                 height: CGFloat(height))))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let buffer = try #require(context.data)
        return Data(bytes: buffer, count: width * height * 4)
    }

    private func rgba(at x: Int, _ y: Int, in pixels: Data, width: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let offset = (y * width + x) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }

    /// Left half red, right half blue — lets crop tests see WHICH region shows.
    private func twoToneImage(width: Int, height: Int) throws -> CGImage {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(context.makeImage())
    }

    private struct EmptyStore: ImageStore {
        struct Empty: Error {}
        func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage { throw Empty() }
        func fullImage(for id: PhotoID) async throws -> CGImage { throw Empty() }
    }

    private func sampleBook(lockFirstSlot: Bool) -> (Book, Page, PrintPreset) {
        let preset = PresetLibrary.preset(id: "blurb-small-square")!
        let id = PhotoID(rawValue: "p1")
        let page = Page(origin: .template(id: "single"),
                        photoSlots: [PhotoSlot(frame: NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                                               photoID: id, isLocked: lockFirstSlot)])
        var book = Book(title: "T", presetID: preset.id, style: .standard)
        book.photoLibrary = [PhotoRef(id: id, source: .file(bookmark: Data()),
                                      pixelWidth: 800, pixelHeight: 600)]
        book.pages = [page]
        return (book, page, preset)
    }

    private var noopInteractions: PageEditingInteractions {
        PageEditingInteractions(onTapPhotoSlot: { _ in }, onDoubleTapPhotoSlot: { _ in },
                                onTapTextSlot: { _ in }, onDoubleTapTextSlot: { _ in },
                                onSetPhotoSlotFrame: { _, _ in }, onSetTextSlotFrame: { _, _ in })
    }

    // MARK: Editing chrome

    @Test func editingChromeDrawsNothingWithoutLocks() throws {
        let (book, page, preset) = sampleBook(lockFirstSlot: false)
        let plain = PageView(page: page, book: book, preset: preset,
                             imageStore: EmptyStore(), highlightedSlotID: nil)
        let editing = plain.editing(noopInteractions)
        let plainPixels = try rgbaPixels(of: plain, width: 300, height: 300)
        let editingPixels = try rgbaPixels(of: editing, width: 300, height: 300)
        #expect(plainPixels == editingPixels)
    }

    @Test func lockBadgeDrawsOnlyInEditingMode() throws {
        let (book, page, preset) = sampleBook(lockFirstSlot: true)
        let plain = PageView(page: page, book: book, preset: preset,
                             imageStore: EmptyStore(), highlightedSlotID: nil)
        let editing = plain.editing(noopInteractions)
        let plainPixels = try rgbaPixels(of: plain, width: 300, height: 300)
        let editingPixels = try rgbaPixels(of: editing, width: 300, height: 300)
        // Browsing mode never shows the badge (Plan 4 behavior preserved) …
        let (bookU, pageU, _) = sampleBook(lockFirstSlot: false)
        let plainUnlocked = PageView(page: pageU, book: bookU, preset: preset,
                                     imageStore: EmptyStore(), highlightedSlotID: nil)
        #expect(try rgbaPixels(of: plainUnlocked, width: 300, height: 300) == plainPixels)
        // … and editing mode draws it.
        #expect(plainPixels != editingPixels)
    }

    // MARK: CroppedPhotoView

    @Test func croppedPhotoViewShowsOnlyTheCropRegion() throws {
        let image = try twoToneImage(width: 200, height: 100)
        // Left half of the photo (all red), square crop region.
        let leftCrop = NormRect(x: 0, y: 0, width: 0.5, height: 1)
        let pixels = try rgbaPixels(of: CroppedPhotoView(image: image, crop: leftCrop),
                                    width: 100, height: 100)
        let center = rgba(at: 50, 50, in: pixels, width: 100)
        #expect(center.r > 200 && center.b < 50, "expected red, got \(center)")
        // Right half → blue.
        let rightCrop = NormRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let rightPixels = try rgbaPixels(of: CroppedPhotoView(image: image, crop: rightCrop),
                                         width: 100, height: 100)
        let rightCenter = rgba(at: 50, 50, in: rightPixels, width: 100)
        #expect(rightCenter.b > 200 && rightCenter.r < 50, "expected blue, got \(rightCenter)")
    }

    // MARK: PageEditingInteractions

    @Test @MainActor func interactionsForwardTextFrameCallback() {
        var captured: (UUID, NormRect)?
        let interactions = PageEditingInteractions(
            onTapPhotoSlot: { _ in }, onDoubleTapPhotoSlot: { _ in },
            onTapTextSlot: { _ in }, onDoubleTapTextSlot: { _ in },
            onSetPhotoSlotFrame: { _, _ in },
            onSetTextSlotFrame: { id, frame in captured = (id, frame) })
        let id = UUID()
        let frame = NormRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)
        interactions.onSetTextSlotFrame(id, frame)
        #expect(captured?.0 == id)
        #expect(captured?.1 == frame)
    }

    // MARK: LayoutWireframeView

    @Test func wireframeRendersDistinctLayouts() throws {
        let hero = LayoutCandidate(origin: .template(id: "hero"),
                                   photoSlotFrames: [NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)],
                                   textSlotFrames: [])
        let twoUp = LayoutCandidate(origin: .template(id: "two-up"),
                                    photoSlotFrames: [NormRect(x: 0.05, y: 0.05, width: 0.425, height: 0.9),
                                                      NormRect(x: 0.525, y: 0.05, width: 0.425, height: 0.9)],
                                    textSlotFrames: [])
        let heroPixels = try rgbaPixels(of: LayoutWireframeView(candidate: hero),
                                        width: 64, height: 64)
        let twoUpPixels = try rgbaPixels(of: LayoutWireframeView(candidate: twoUp),
                                         width: 64, height: 64)
        #expect(heroPixels != twoUpPixels)
        // The hero wireframe's center is the filled slot, not the white page.
        let center = rgba(at: 32, 32, in: heroPixels, width: 64)
        #expect(center.r < 250 || center.g < 250 || center.b < 250)
    }
}
