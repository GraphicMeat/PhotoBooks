import CoreGraphics
import Foundation
import PhotoBookCore
import PhotoBookRender

/// Deterministic `ImageStore` stub: each photo ID maps to a solid-color
/// image of fixed pixel dimensions. No disk, no providers — renders the
/// same bytes on every run, which is what golden tests need.
struct SolidColorImageStore: ImageStore {

    struct Entry: Sendable {
        var red: Double
        var green: Double
        var blue: Double
        var pixelWidth: Int
        var pixelHeight: Int

        init(red: Double, green: Double, blue: Double, pixelWidth: Int, pixelHeight: Int) {
            self.red = red
            self.green = green
            self.blue = blue
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }
    }

    enum StoreError: Error {
        case unknownPhotoID(PhotoID)
        case renderFailed
    }

    let entries: [PhotoID: Entry]

    func thumbnail(for id: PhotoID, maxPixelSize: Int) async throws -> CGImage {
        guard let entry = entries[id] else { throw StoreError.unknownPhotoID(id) }
        // Downscale like a real store would, preserving aspect.
        let longest = max(entry.pixelWidth, entry.pixelHeight)
        let scale = min(1, Double(maxPixelSize) / Double(longest))
        return try Self.render(
            entry: entry,
            width: max(1, Int((Double(entry.pixelWidth) * scale).rounded())),
            height: max(1, Int((Double(entry.pixelHeight) * scale).rounded()))
        )
    }

    func fullImage(for id: PhotoID) async throws -> CGImage {
        guard let entry = entries[id] else { throw StoreError.unknownPhotoID(id) }
        return try Self.render(entry: entry, width: entry.pixelWidth, height: entry.pixelHeight)
    }

    static func render(entry: Entry, width: Int, height: Int) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw StoreError.renderFailed }
        context.setFillColor(CGColor(srgbRed: entry.red, green: entry.green, blue: entry.blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw StoreError.renderFailed }
        return image
    }
}
