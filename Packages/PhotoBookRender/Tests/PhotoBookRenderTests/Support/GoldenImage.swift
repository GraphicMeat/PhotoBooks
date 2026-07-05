import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// PNG golden-image comparison with a per-pixel tolerance.
///
/// Goldens live next to the test sources (`Tests/PhotoBookRenderTests/Goldens/`)
/// and are addressed via `#filePath`, not `Bundle.module` — recording and
/// comparing must hit the same files.
///
/// Recording: `RECORD_GOLDEN=1 swift test ...` writes/overwrites the golden
/// and records a test issue (so a recording run can never silently "pass").
/// Inspect the PNG, then commit it.
///
/// On mismatch the actual image is written next to the golden as
/// `<name>.actual.png` for eyeballing; `.actual.png` files are git-ignored.
enum GoldenImage {

    static var goldensDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Support/
            .deletingLastPathComponent()   // test target root
            .appendingPathComponent("Goldens", isDirectory: true)
    }

    /// Compares `image` against the named golden. `maxChannelDelta` is the
    /// per-channel tolerance (RGBA, 0–255) under which two pixels count as
    /// equal; `maxMismatchedFraction` is the share of pixels allowed to
    /// exceed it (anti-aliasing of text and curved edges may shift by a few
    /// pixels across OS releases without the layout being wrong).
    static func assertMatchesGolden(
        _ image: CGImage,
        named name: String,
        maxChannelDelta: Int = 8,
        maxMismatchedFraction: Double = 0.005,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let goldenURL = goldensDirectory.appendingPathComponent("\(name).png")

        if ProcessInfo.processInfo.environment["RECORD_GOLDEN"] == "1" {
            try FileManager.default.createDirectory(at: goldensDirectory,
                                                    withIntermediateDirectories: true)
            try writePNG(image, to: goldenURL)
            Issue.record(
                "Recorded golden '\(name).png'. Inspect it, commit it, and rerun without RECORD_GOLDEN.",
                sourceLocation: sourceLocation)
            return
        }

        guard FileManager.default.fileExists(atPath: goldenURL.path) else {
            Issue.record(
                "Missing golden '\(name).png'. Record it: RECORD_GOLDEN=1 swift test --package-path Packages/PhotoBookRender",
                sourceLocation: sourceLocation)
            return
        }

        let golden = try loadPNG(goldenURL)
        guard golden.width == image.width, golden.height == image.height else {
            try writePNG(image, to: actualURL(for: name))
            Issue.record(
                "Golden '\(name)' size \(golden.width)×\(golden.height) ≠ actual \(image.width)×\(image.height). Actual written to \(actualURL(for: name).path).",
                sourceLocation: sourceLocation)
            return
        }

        let goldenPixels = rgbaPixels(of: golden)
        let actualPixels = rgbaPixels(of: image)
        var mismatched = 0
        let pixelCount = golden.width * golden.height
        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            for channel in 0..<4 {
                let delta = abs(Int(goldenPixels[offset + channel]) - Int(actualPixels[offset + channel]))
                if delta > maxChannelDelta {
                    mismatched += 1
                    break
                }
            }
        }
        let fraction = Double(mismatched) / Double(pixelCount)
        if fraction > maxMismatchedFraction {
            try writePNG(image, to: actualURL(for: name))
        }
        #expect(
            fraction <= maxMismatchedFraction,
            "\(mismatched)/\(pixelCount) pixels (\(String(format: "%.3f", fraction * 100))%) differ from golden '\(name)' by more than \(maxChannelDelta)/channel. Actual written to \(actualURL(for: name).path).",
            sourceLocation: sourceLocation)
    }

    private static func actualURL(for name: String) -> URL {
        goldensDirectory.appendingPathComponent("\(name).actual.png")
    }

    // MARK: PNG I/O

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw GoldenError.writeFailed(url) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GoldenError.writeFailed(url) }
    }

    static func loadPNG(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw GoldenError.readFailed(url) }
        return image
    }

    enum GoldenError: Error {
        case writeFailed(URL)
        case readFailed(URL)
    }

    /// Whole image as RGBA8 (sRGB, premultiplied-last) bytes, row 0 = top —
    /// re-rendering normalizes whatever byte layout the decoder produced.
    static func rgbaPixels(of image: CGImage) -> [UInt8] {
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
}
