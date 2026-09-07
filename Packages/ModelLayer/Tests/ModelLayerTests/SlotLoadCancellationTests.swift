import CoreGraphics
import Foundation
import ImageIO
import PhotoBookCore
import PhotoBookImport
import Testing
import UniformTypeIdentifiers
@testable import ModelLayer
@testable import PhotoBookRender

/// End-to-end guard for the "photos are placeholders until you switch pages"
/// bug, across the REAL stack a slot uses on screen: `AppImageStore` →
/// `FileSystemProvider` → ImageIO, with a real file on disk and a real
/// cancelled task.
///
/// On document open the editor canvas settles its geometry over the first
/// frames, so `AsyncPhotoSlotView`'s load key (photo id + bucketed pixel
/// size) changes while the first decode is in flight and SwiftUI cancels it.
/// This pins what that cancellation actually throws — and that the view's
/// reducer treats it as "ignore", not "failed".
@Suite struct SlotLoadCancellationTests {

    /// Suspends until `open()`, ignoring cancellation — lets a test cancel a
    /// task that is provably still parked before its decode starts.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    private func makeFixtureRef(in folder: URL) throws -> PhotoRef {
        let url = folder.appendingPathComponent("fixture.png")
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 512, height: 384,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 384))
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return try MetadataReader.photoRef(forFileAt: url, bookmark: url.bookmarkData())
    }

    @Test func cancelledSlotLoadIsIgnoredNotLatchedAsMissing() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlotLoadCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let ref = try makeFixtureRef(in: folder)
        let refs: [PhotoID: PhotoRef] = [ref.id: ref]
        let store = AppImageStore(fileSystemProvider: FileSystemProvider(),
                                  photoKitProvider: PhotoKitProvider(),
                                  refProvider: { refs })

        // A load parked before its decode, cancelled, then released: exactly
        // the shape of a key change landing on an in-flight thumbnail.
        let gate = Gate()
        let load = Task { () -> CGImage in
            await gate.wait()
            return try await store.thumbnail(for: ref.id, maxPixelSize: 1024)
        }
        load.cancel()
        await gate.open()

        do {
            _ = try await load.value
            Issue.record("a cancelled decode should throw")
        } catch {
            // What the provider contract actually throws...
            #expect(error as? PhotoProviderError == .cancelled)
            // ...which is why `catch is CancellationError` never matched it.
            #expect(!(error is CancellationError))
            // ...and what the slot must do with it: nothing.
            #expect(SlotLoadOutcome.of(error: error, taskCancelled: true) == .ignore)
        }

        // The photo itself is fine: the next key's load still succeeds.
        let image = try await store.thumbnail(for: ref.id, maxPixelSize: 1024)
        #expect(image.width > 0)
    }
}
