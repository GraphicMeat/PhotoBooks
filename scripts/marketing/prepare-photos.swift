// Copies marketing photos for a capture run: upscales each to a camera-like
// long edge (so print preflight sees enough pixels on 7-inch pages and full
// spreads) and stamps a story-order EXIF capture date (the stock files carry
// none, so Photos and curation would otherwise order them by import time).
// The source files are never modified.
//
// Usage: xcrun swift scripts/marketing/prepare-photos.swift <src> <dst> [long-edge]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: prepare-photos.swift <src> <dst> [long-edge]\n".utf8))
    exit(2)
}
let source = URL(fileURLWithPath: arguments[1], isDirectory: true)
let destination = URL(fileURLWithPath: arguments[2], isDirectory: true)
let longEdge = arguments.count >= 4 ? Double(arguments[3]) ?? 3600 : 3600
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
    .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

for (index, file) in files.enumerated() {
    guard let imageSource = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        FileHandle.standardError.write(Data("cannot read \(file.path)\n".utf8))
        exit(1)
    }
    let scale = max(1, longEdge / Double(max(image.width, image.height)))
    let width = Int((Double(image.width) * scale).rounded())
    let height = Int((Double(image.height) * scale).rounded())
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: sRGB,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Four days by the sea, twelve photos a day from 9:00, 50 minutes apart.
    let day = 18 + index / 12
    let minutes = 9 * 60 + (index % 12) * 50
    let stamp = String(format: "2026:07:%02d %02d:%02d:00", day, minutes / 60, minutes % 60)
    let properties: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.9,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: stamp,
                                         kCGImagePropertyExifDateTimeDigitized: stamp],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp]
    ]
    let output = destination.appendingPathComponent(file.lastPathComponent)
    guard let scaled = context.makeImage(),
          let writer = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { exit(1) }
    CGImageDestinationAddImage(writer, scaled, properties as CFDictionary)
    guard CGImageDestinationFinalize(writer) else { exit(1) }
}
print("prepared \(files.count) photos in \(destination.path)")
