// Writes deterministic, mixed-aspect PNG "photos" for the Duo smoke run.
// Usage: xcrun swift scripts/duo/make-fixtures.swift <folder> [count]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-fixtures.swift <folder> [count]\n".utf8))
    exit(2)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
let count = arguments.count >= 3 ? Int(arguments[2]) ?? 16 : 16
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

// Landscape, portrait and square sizes so the layout engine mixes templates.
let sizes = [(1200, 800), (800, 1200), (1000, 1000), (1500, 900), (900, 1350)]
let space = CGColorSpace(name: CGColorSpace.sRGB)!

for index in 0..<count {
    let (width, height) = sizes[index % sizes.count]
    let hue = Double(index) / Double(count)
    func color(_ h: Double, _ s: Double, _ b: Double) -> CGColor {
        // HSB → RGB, enough for test images.
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = b * (1 - s), q = b * (1 - f * s), t = b * (1 - (1 - f) * s)
        let rgb = [(b, t, p), (q, b, p), (p, b, t), (p, q, b), (t, p, b), (b, p, q)][i]
        return CGColor(colorSpace: space, components: [rgb.0, rgb.1, rgb.2, 1])!
    }
    guard let context = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let gradient = CGGradient(colorsSpace: space,
                                    colors: [color(hue, 0.55, 0.95),
                                             color((hue + 0.12).truncatingRemainder(dividingBy: 1), 0.75, 0.45)] as CFArray,
                                    locations: [0, 1])
    else { exit(1) }
    context.drawLinearGradient(gradient, start: .zero,
                               end: CGPoint(x: width, y: height), options: [])
    // A "subject" disc plus a horizon band, so frames read as photos.
    context.setFillColor(color((hue + 0.5).truncatingRemainder(dividingBy: 1), 0.35, 1))
    let radius = Double(min(width, height)) * 0.18
    context.fillEllipse(in: CGRect(x: Double(width) * 0.62 - radius, y: Double(height) * 0.6 - radius,
                                   width: radius * 2, height: radius * 2))
    context.setFillColor(CGColor(gray: 0, alpha: 0.18))
    context.fill(CGRect(x: 0, y: 0, width: Double(width), height: Double(height) * 0.28))

    let url = folder.appendingPathComponent(String(format: "duo-%02d.png", index))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }
}
print("wrote \(count) fixtures to \(folder.path)")
