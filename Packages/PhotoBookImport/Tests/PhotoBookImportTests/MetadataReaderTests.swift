import Foundation
import PhotoBookCore
import Testing
@testable import PhotoBookImport

@Suite struct MetadataReaderTests {

    private func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: - Dimensions

    @Test func uprightImageKeepsStoredDimensions() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("upright.tif"), pixelWidth: 100, pixelHeight: 60)

        let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: Data([0x01]))
        #expect(ref.pixelWidth == 100)
        #expect(ref.pixelHeight == 60)
    }

    @Test func orientationSixSwapsPixelDimensions() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Stored 100×60, EXIF orientation 6 (90° CW to display) → displays 60×100.
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("rotated.tif"),
            pixelWidth: 100, pixelHeight: 60, orientation: 6)

        let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: Data([0x01]))
        #expect(ref.pixelWidth == 60)
        #expect(ref.pixelHeight == 100)
        #expect(abs(ref.aspectRatio - 0.6) < 1e-12)
    }

    @Test func mirrorOrientationsDoNotSwapDimensions() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Orientation 2 (horizontal mirror) flips but does not transpose.
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("mirrored.tif"),
            pixelWidth: 100, pixelHeight: 60, orientation: 2)

        let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: Data([0x01]))
        #expect(ref.pixelWidth == 100)
        #expect(ref.pixelHeight == 60)
    }

    // MARK: - Capture date fallback chain

    @Test func exifDateTimeOriginalParsedAsUTC() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("exif.tif"), pixelWidth: 8, pixelHeight: 8,
            exifDateTimeOriginal: "2024:07:15 14:30:05")

        let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: Data())
        #expect(ref.captureDate == utcDate(year: 2024, month: 7, day: 15, hour: 14, minute: 30, second: 5))
    }

    @Test func exifDateWinsOverTiffDate() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("both.tif"), pixelWidth: 8, pixelHeight: 8,
            exifDateTimeOriginal: "2024:07:15 14:30:05",
            tiffDateTime: "2020:01:02 03:04:05")

        let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: Data())
        #expect(ref.captureDate == utcDate(year: 2024, month: 7, day: 15, hour: 14, minute: 30, second: 5))
    }

    @Test func tiffDateUsedWhenExifMissing() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("tiffdate.tif"), pixelWidth: 8, pixelHeight: 8,
            tiffDateTime: "2020:01:02 03:04:05")

        let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: Data())
        #expect(ref.captureDate == utcDate(year: 2020, month: 1, day: 2, hour: 3, minute: 4, second: 5))
    }

    @Test func fileCreationDateUsedWhenNoMetadataDates() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("nodate.tif"), pixelWidth: 8, pixelHeight: 8)

        let creationDate = try #require(
            try url.resourceValues(forKeys: [.creationDateKey]).creationDate)
        let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: Data())
        let captureDate = try #require(ref.captureDate)
        #expect(abs(captureDate.timeIntervalSince(creationDate)) < 1.0)
        // The final nil fallback (no creation date either) is unreachable on
        // APFS, which always stamps creation dates; it exists for exotic
        // filesystems and is covered by code inspection.
    }

    @Test func unparseableExifDateFallsThrough() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Garbage EXIF date, valid TIFF date → TIFF date wins.
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("garbage-exif.tif"), pixelWidth: 8, pixelHeight: 8,
            exifDateTimeOriginal: "not a date",
            tiffDateTime: "2020:01:02 03:04:05")

        let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: Data())
        #expect(ref.captureDate == utcDate(year: 2020, month: 1, day: 2, hour: 3, minute: 4, second: 5))
    }

    // MARK: - PhotoID derivation

    @Test func photoIDKnownAnswer() {
        // SHA-256("/fixtures/IMG_0001.jpg") = 4c2ae0705e19a4d6… — first 16 hex chars.
        let id = MetadataReader.photoID(forFileAt: URL(fileURLWithPath: "/fixtures/IMG_0001.jpg"))
        #expect(id.rawValue == "4c2ae0705e19a4d6")
    }

    @Test func photoIDIsDeterministicAndPathSensitive() {
        let a1 = MetadataReader.photoID(forFileAt: URL(fileURLWithPath: "/photos/a.jpg"))
        let a2 = MetadataReader.photoID(forFileAt: URL(fileURLWithPath: "/photos/a.jpg"))
        let b = MetadataReader.photoID(forFileAt: URL(fileURLWithPath: "/photos/b.jpg"))
        #expect(a1 == a2)
        #expect(a1 != b)
        #expect(a1.rawValue.count == 16)
        #expect(a1.rawValue.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func photoIDUsesStandardizedPath() {
        let direct = MetadataReader.photoID(forFileAt: URL(fileURLWithPath: "/photos/album/a.jpg"))
        let indirect = MetadataReader.photoID(
            forFileAt: URL(fileURLWithPath: "/photos/extra/../album/./a.jpg"))
        #expect(direct == indirect)
    }

    // MARK: - Bookmark passthrough and errors

    @Test func bookmarkIsStoredVerbatim() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FixtureFactory.writeImage(
            at: folder.appendingPathComponent("bm.tif"), pixelWidth: 8, pixelHeight: 8)

        let bookmark = Data([0xCA, 0xFE, 0xBA, 0xBE])
        let ref = try MetadataReader.photoRef(forFileAt: url, bookmark: bookmark)
        #expect(ref.source == .file(bookmark: bookmark))
        #expect(ref.isMissing == false)
    }

    @Test func missingFileThrowsAssetUnavailable() {
        let url = URL(fileURLWithPath: "/nonexistent/definitely-not-here.jpg")
        let expectedID = MetadataReader.photoID(forFileAt: url)
        #expect(throws: PhotoProviderError.assetUnavailable(expectedID)) {
            _ = try MetadataReader.photoRef(forFileAt: url, bookmark: Data())
        }
    }

    @Test func nonImageFileThrowsAssetUnavailable() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("fake.jpg")
        try Data("this is not an image".utf8).write(to: url)

        #expect(throws: PhotoProviderError.assetUnavailable(MetadataReader.photoID(forFileAt: url))) {
            _ = try MetadataReader.photoRef(forFileAt: url, bookmark: Data())
        }
    }
}
