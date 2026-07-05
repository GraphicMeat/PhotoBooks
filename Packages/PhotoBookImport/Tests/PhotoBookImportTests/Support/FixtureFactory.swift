import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FixtureError: Error {
    case renderFailed
    case writeFailed(URL)
}

/// Generates fixture images at runtime — no binary fixtures are checked in.
/// Solid blue with an opaque red top-left-quadrant marker (the marker makes
/// orientation transforms observable in pixel tests), written via
/// `CGImageDestination` with optional EXIF/TIFF metadata.
///
/// TIFF is the default container: lossless pixels (exact color assertions)
/// and native orientation-tag support. JPEG/PNG are used where the *format*
/// matters; HEIC is avoided because HEIC encoding availability varies by
/// host hardware.
enum FixtureFactory {

    /// Unique per-test temp folder.
    static func makeTempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoBookImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Renders the fixture image: opaque blue background, opaque red
    /// top-left quadrant. CGContext's origin is bottom-left, so the TOP-left
    /// quadrant is y ∈ [height/2, height).
    static func render(pixelWidth: Int, pixelHeight: Int) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelWidth,
                  height: pixelHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw FixtureError.renderFailed }

        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(
            x: 0,
            y: pixelHeight - pixelHeight / 2,
            width: pixelWidth / 2,
            height: pixelHeight / 2
        ))

        guard let image = context.makeImage() else { throw FixtureError.renderFailed }
        return image
    }

    /// Writes a generated fixture image with optional metadata. `pixelWidth`
    /// and `pixelHeight` are the STORED dimensions; if `orientation` is 5–8
    /// the image *displays* transposed.
    @discardableResult
    static func writeImage(
        at url: URL,
        pixelWidth: Int,
        pixelHeight: Int,
        type: UTType = .tiff,
        orientation: UInt32? = nil,
        exifDateTimeOriginal: String? = nil,
        tiffDateTime: String? = nil
    ) throws -> URL {
        let image = try render(pixelWidth: pixelWidth, pixelHeight: pixelHeight)

        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if let exifDateTimeOriginal {
            properties[kCGImagePropertyExifDictionary] =
                [kCGImagePropertyExifDateTimeOriginal: exifDateTimeOriginal]
        }
        if let tiffDateTime {
            properties[kCGImagePropertyTIFFDictionary] =
                [kCGImagePropertyTIFFDateTime: tiffDateTime]
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ) else { throw FixtureError.writeFailed(url) }
        CGImageDestinationAddImage(destination, image, properties.isEmpty ? nil : properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.writeFailed(url) }
        return url
    }
}

/// Reads single pixels out of a `CGImage` by re-rendering it into a fresh
/// RGBA8 sRGB buffer — normalizes whatever byte layout the decoder produced,
/// so images from different decode paths compare cleanly.
enum PixelSampler {

    /// Pixel at (x, y) in top-left-origin image coordinates.
    static func rgba(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        let pixels = allPixels(of: image)
        let offset = (y * image.width + x) * 4
        return Array(pixels[offset..<(offset + 4)])
    }

    /// Whole image as RGBA8 bytes, row 0 = top scanline.
    static func allPixels(of image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { pointer in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: pointer.baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: width * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return buffer
    }

    /// Max per-channel difference between two same-sized images (255 if
    /// dimensions differ).
    static func maxChannelDelta(_ a: CGImage, _ b: CGImage) -> Int {
        guard a.width == b.width, a.height == b.height else { return 255 }
        let pa = allPixels(of: a)
        let pb = allPixels(of: b)
        var maxDelta = 0
        for index in pa.indices {
            maxDelta = max(maxDelta, abs(Int(pa[index]) - Int(pb[index])))
        }
        return maxDelta
    }
}
