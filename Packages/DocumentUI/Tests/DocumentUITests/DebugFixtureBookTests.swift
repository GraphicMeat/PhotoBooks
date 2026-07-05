import CoreGraphics
import Foundation
import ImageIO
import PhotoBookCore
import Testing
import UniformTypeIdentifiers
@testable import DocumentUI

@Suite struct DebugFixtureBookTests {

    private func writeFixture(at url: URL, width: Int, height: Int) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let destination = CGImageDestinationCreateWithURL(
                  url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    @Test func buildsDeterministicBookFromFolder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DebugFixtureBookTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        for index in 1...10 {
            // Mix portrait and landscape so the engine exercises different
            // layouts and generates enough pages to satisfy the >= 3 assertion.
            let landscape = index.isMultiple(of: 2)
            try writeFixture(at: folder.appendingPathComponent("img-\(index).png"),
                             width: landscape ? 320 : 240,
                             height: landscape ? 240 : 320)
        }
        // A non-image file must be ignored.
        try Data("not an image".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        let book = DebugFixtureBook.makeBook(fixtureFolder: folder)
        #expect(book.title == "Fixture Book")
        #expect(book.photoLibrary.count == 10)
        #expect(book.pages.count >= 3)               // cover + interior pages
        #expect(book.pages.first?.role == .cover)
    }
}
