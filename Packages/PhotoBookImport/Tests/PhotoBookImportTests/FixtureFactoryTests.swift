import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@Suite struct FixtureFactoryTests {

    @Test func writesReadableTIFFWithExactPixels() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("fixture.tif")
        try FixtureFactory.writeImage(at: url, pixelWidth: 40, pixelHeight: 20)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 40)
        #expect(image.height == 20)

        // TIFF is lossless: the red top-left marker and blue background are exact.
        let topLeft = PixelSampler.rgba(of: image, x: 5, y: 5)
        #expect(topLeft == [255, 0, 0, 255])
        let bottomRight = PixelSampler.rgba(of: image, x: 35, y: 15)
        #expect(bottomRight == [0, 0, 255, 255])
    }

    @Test func orientationTagRoundTrips() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("oriented.tif")
        try FixtureFactory.writeImage(at: url, pixelWidth: 30, pixelHeight: 10, orientation: 6)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyOrientation] as? UInt32 == 6)
    }

    @Test func exifAndTiffDatesRoundTrip() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("dated.tif")
        try FixtureFactory.writeImage(
            at: url, pixelWidth: 8, pixelHeight: 8,
            exifDateTimeOriginal: "2024:07:15 14:30:05",
            tiffDateTime: "2020:01:02 03:04:05"
        )

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] as? String == "2024:07:15 14:30:05")
        let tiff = try #require(properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        #expect(tiff[kCGImagePropertyTIFFDateTime] as? String == "2020:01:02 03:04:05")
    }

    @Test func writesJPEGAndPNGContainers() throws {
        let folder = try FixtureFactory.makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let jpeg = folder.appendingPathComponent("photo.jpg")
        try FixtureFactory.writeImage(at: jpeg, pixelWidth: 16, pixelHeight: 12, type: .jpeg)
        let png = folder.appendingPathComponent("shot.png")
        try FixtureFactory.writeImage(at: png, pixelWidth: 16, pixelHeight: 12, type: .png)

        for url in [jpeg, png] {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == 16)
            #expect(image.height == 12)
        }
    }
}
