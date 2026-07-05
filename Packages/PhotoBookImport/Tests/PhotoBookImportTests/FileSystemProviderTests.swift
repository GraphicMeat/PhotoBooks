import CoreGraphics
import Foundation
import ImageIO
import PhotoBookCore
import Testing
@testable import PhotoBookImport

@Suite struct FileSystemProviderTests {

    // MARK: - Collections

    @Test func makeCollectionRegistersFolder() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("a.tif"), pixelWidth: 8, pixelHeight: 8)
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("b.tif"), pixelWidth: 8, pixelHeight: 8)
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)

        #expect(collection.title == folder.lastPathComponent)
        #expect(collection.estimatedCount == 2)        // txt not counted
        #expect(collection.id == MetadataReader.photoID(forFileAt: folder).rawValue)
        #expect(try await provider.collections() == [collection])
    }

    @Test func reRegisteringSameFolderDoesNotDuplicate() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("a.tif"), pixelWidth: 8, pixelHeight: 8)

        let provider = FileSystemProvider()
        let first = try provider.makeCollection(fromFolder: folder)
        let second = try provider.makeCollection(fromFolder: folder)

        #expect(first.id == second.id)
        #expect(try await provider.collections().count == 1)
    }

    @Test func collectionsStartEmptyAndSortByTitle() async throws {
        let provider = FileSystemProvider()
        #expect(try await provider.collections().isEmpty)

        let parent = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: parent) }
        for name in ["zebra", "alpha"] {
            let sub = parent.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            _ = try provider.makeCollection(fromFolder: sub)
        }
        #expect(try await provider.collections().map(\.title) == ["alpha", "zebra"])
    }

    @Test func unknownCollectionThrowsAssetUnavailable() async {
        let provider = FileSystemProvider()
        let ghost = PhotoCollection(id: "no-such-collection", title: "Ghost")
        await #expect(throws: PhotoProviderError.assetUnavailable(PhotoID(rawValue: "no-such-collection"))) {
            _ = try await provider.photoRefs(in: ghost)
        }
    }

    @Test func unreadableFolderThrows() {
        let provider = FileSystemProvider()
        let missing = URL(fileURLWithPath: "/nonexistent/folder-\(UUID().uuidString)")
        #expect(throws: PhotoProviderError.self) {
            _ = try provider.makeCollection(fromFolder: missing)
        }
    }

    // MARK: - Enumeration

    @Test func photoRefsFiltersExtensionsAndSortsByFilename() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Created deliberately out of name order; expect sorted output.
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("03-c.png"), pixelWidth: 8, pixelHeight: 8, type: .png)
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("01-a.jpg"), pixelWidth: 8, pixelHeight: 8, type: .jpeg)
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("02-b.tif"), pixelWidth: 8, pixelHeight: 8)
        // Uppercase extension must match (lowercased comparison).
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("04-D.TIF"), pixelWidth: 8, pixelHeight: 8)
        // Non-image extensions are skipped.
        try Data("plain text".utf8).write(to: folder.appendingPathComponent("00-notes.txt"))
        try Data([0x00, 0x01]).write(to: folder.appendingPathComponent("00-data.bin"))
        // GIF is not an imported format.
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("00-anim.gif"), pixelWidth: 8, pixelHeight: 8, type: .gif)

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)
        let refs = try await provider.photoRefs(in: collection)

        let names = try refs.map { ref -> String in
            guard case .file(let bookmark) = ref.source else {
                throw PhotoProviderError.assetUnavailable(ref.id)
            }
            return try FileSystemProvider.resolveBookmark(bookmark, refID: ref.id).lastPathComponent
        }
        #expect(names == ["01-a.jpg", "02-b.tif", "03-c.png", "04-D.TIF"])
    }

    @Test func corruptImageFilesAreSkippedNotFatal() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("good.tif"), pixelWidth: 8, pixelHeight: 8)
        // Image extension, garbage content: skipped, does not abort the import.
        try Data("garbage bytes pretending to be a JPEG".utf8)
            .write(to: folder.appendingPathComponent("broken.jpg"))

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)
        let refs = try await provider.photoRefs(in: collection)
        #expect(refs.count == 1)
        #expect(refs[0].pixelWidth == 8)
    }

    @Test func subfoldersAreNotEnumerated() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("top.tif"), pixelWidth: 8, pixelHeight: 8)
        let nested = folder.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FixtureFactory.writeImage(at: nested.appendingPathComponent("deep.tif"), pixelWidth: 8, pixelHeight: 8)

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)
        let refs = try await provider.photoRefs(in: collection)
        #expect(refs.count == 1)
    }

    @Test func directoryNamedWithImageExtensionIsNotCountedOrEnumerated() async throws {
        // A directory whose name ends in an image extension (e.g. "notaphoto.jpg/")
        // must not be counted as a photo in estimatedCount or returned by photoRefs.
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // One legitimate image file.
        try FixtureFactory.writeImage(at: folder.appendingPathComponent("real.tif"), pixelWidth: 8, pixelHeight: 8)
        // A directory whose name looks like an image file — must be excluded.
        let dirLookingLikeImage = folder.appendingPathComponent("notaphoto.jpg", isDirectory: true)
        try FileManager.default.createDirectory(at: dirLookingLikeImage, withIntermediateDirectories: true)

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)

        // estimatedCount must count only the real file.
        #expect(collection.estimatedCount == 1)

        // photoRefs must enumerate only the real file.
        let refs = try await provider.photoRefs(in: collection)
        #expect(refs.count == 1)
    }

    @Test func photoRefsCarryMetadata() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("meta.tif"),
            pixelWidth: 100, pixelHeight: 60, orientation: 6,
            exifDateTimeOriginal: "2024:07:15 14:30:05")

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)
        let refs = try await provider.photoRefs(in: collection)

        let ref = try #require(refs.first)
        #expect(ref.id == MetadataReader.photoID(forFileAt: url))
        #expect(ref.pixelWidth == 60)      // orientation 6 → display dims
        #expect(ref.pixelHeight == 100)
        #expect(ref.captureDate != nil)
    }

    // MARK: - Thumbnails

    @Test func thumbnailRespectsMaxPixelSize() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("big.jpg"),
            pixelWidth: 400, pixelHeight: 300, type: .jpeg)

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)
        let ref = try #require(try await provider.photoRefs(in: collection).first)

        let thumbnail = try await provider.thumbnail(for: ref, maxPixelSize: 100)
        #expect(max(thumbnail.width, thumbnail.height) == 100)
        #expect(thumbnail.width == 100)    // aspect preserved: 400×300 → 100×75
        #expect(thumbnail.height == 75)
    }

    @Test func thumbnailBakesOrientationIntoPixels() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Stored 100×60 with orientation 6 → upright thumbnail is portrait.
        try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("rot.tif"),
            pixelWidth: 100, pixelHeight: 60, orientation: 6)

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)
        let ref = try #require(try await provider.photoRefs(in: collection).first)

        // maxPixelSize larger than the image: ImageIO does not upscale.
        let thumbnail = try await provider.thumbnail(for: ref, maxPixelSize: 200)
        #expect(thumbnail.width == 60)
        #expect(thumbnail.height == 100)
    }

    @Test func thumbnailForDeletedFileThrowsAssetUnavailable() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("gone.tif"), pixelWidth: 8, pixelHeight: 8)

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)
        let ref = try #require(try await provider.photoRefs(in: collection).first)

        try FileManager.default.removeItem(at: url)

        await #expect(throws: PhotoProviderError.assetUnavailable(ref.id)) {
            _ = try await provider.thumbnail(for: ref, maxPixelSize: 100)
        }
    }

    @Test func garbageBookmarkThrowsAssetUnavailable() async {
        let provider = FileSystemProvider()
        let ref = PhotoRef(
            id: PhotoID(rawValue: "garbage"),
            source: .file(bookmark: Data([0xDE, 0xAD, 0xBE, 0xEF])),
            pixelWidth: 10, pixelHeight: 10)
        await #expect(throws: PhotoProviderError.assetUnavailable(PhotoID(rawValue: "garbage"))) {
            _ = try await provider.thumbnail(for: ref, maxPixelSize: 100)
        }
    }

    @Test func photoKitRefIsRejected() async {
        let provider = FileSystemProvider()
        let ref = PhotoRef(
            id: PhotoID(rawValue: "pk"),
            source: .photoKit(localIdentifier: "ABC-123"),
            pixelWidth: 10, pixelHeight: 10)
        await #expect(throws: PhotoProviderError.assetUnavailable(PhotoID(rawValue: "pk"))) {
            _ = try await provider.fullImage(for: ref)
        }
    }

    // MARK: - Full image + orientation normalization

    @Test func fullImageReturnsFullResolution() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("full.tif"), pixelWidth: 320, pixelHeight: 240)

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)
        let ref = try #require(try await provider.photoRefs(in: collection).first)

        let image = try await provider.fullImage(for: ref)
        #expect(image.width == 320)
        #expect(image.height == 240)
    }

    @Test func fullImageAppliesOrientationSix() async throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Stored 100×60, red top-left-quadrant marker, orientation 6 (90° CW
        // to display). After normalization: 60×100, and the red marker lands
        // in the display's top-RIGHT quadrant.
        try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("rot6.tif"),
            pixelWidth: 100, pixelHeight: 60, orientation: 6)

        let provider = FileSystemProvider()
        let collection = try provider.makeCollection(fromFolder: folder)
        let ref = try #require(try await provider.photoRefs(in: collection).first)

        let image = try await provider.fullImage(for: ref)
        #expect(image.width == 60)
        #expect(image.height == 100)

        let topRight = PixelSampler.rgba(of: image, x: 55, y: 10)
        #expect(topRight == [255, 0, 0, 255])      // marker rotated into place
        let topLeft = PixelSampler.rgba(of: image, x: 5, y: 10)
        #expect(topLeft == [0, 0, 255, 255])       // background
        let bottomRight = PixelSampler.rgba(of: image, x: 55, y: 90)
        #expect(bottomRight == [0, 0, 255, 255])   // background
    }

    @Test func manualNormalizationMatchesImageIOForAllOrientations() async throws {
        // Cross-validation: for every EXIF orientation 1–8, our manual
        // CGAffineTransform normalization must produce pixel-identical output
        // to ImageIO's own kCGImageSourceCreateThumbnailWithTransform decode.
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let provider = FileSystemProvider()

        for orientation: UInt32 in 1...8 {
            let url = try FixtureFactory.writeImage(
                at: folder.appendingPathComponent("o\(orientation).tif"),
                pixelWidth: 8, pixelHeight: 6, orientation: orientation)
            let bookmark = try FileSystemProvider.makeBookmark(for: url)
            let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: bookmark)

            let manual = try await provider.fullImage(for: ref)

            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64
            ]
            let reference = try #require(
                CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))

            #expect(manual.width == reference.width, "orientation \(orientation)")
            #expect(manual.height == reference.height, "orientation \(orientation)")
            #expect(PixelSampler.maxChannelDelta(manual, reference) <= 2,
                    "orientation \(orientation): pixels diverge from ImageIO transform")
        }
    }
}
