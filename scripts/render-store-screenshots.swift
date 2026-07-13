#!/usr/bin/env swift

import AppKit
import Foundation

private struct Template: Decodable {
    let id: String
    let source: String
    let layout: String
    let background: [String]
    let accent: String
}

private struct CopyFile: Decodable {
    struct Entry: Decodable { let headline: String; let subtext: String }
    let locale: String
    let state: String
    let screenshots: [String: Entry]
}

private enum RenderError: Error, CustomStringConvertible {
    case usage, badColor(String), missingCopy(String), invalidTemplate(String), cannotWrite(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: render-store-screenshots.swift --templates DIR --copy FILE --raw DIR --output DIR"
        case .badColor(let value): return "invalid hex color: \(value)"
        case .missingCopy(let id): return "copy is missing screenshot id \(id)"
        case .invalidTemplate(let value): return "invalid template: \(value)"
        case .cannotWrite(let value): return "could not write PNG: \(value)"
        }
    }
}

private extension NSColor {
    convenience init(hex: String) throws {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = Int(value, radix: 16) else {
            throw RenderError.badColor(hex)
        }
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                  green: CGFloat((rgb >> 8) & 255) / 255,
                  blue: CGFloat(rgb & 255) / 255,
                  alpha: 1)
    }
}

private let canvas = CGSize(width: 2880, height: 1800)

private func topRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvas.height - y - height, width: width, height: height)
}

private func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          CommandLine.arguments.indices.contains(index + 1) else { return nil }
    return CommandLine.arguments[index + 1]
}

private func drawText(_ value: String, in rect: NSRect, font: NSFont,
                      color: NSColor, lineHeight: CGFloat, alignment: NSTextAlignment) {
    let style = NSMutableParagraphStyle()
    style.alignment = alignment
    style.minimumLineHeight = lineHeight
    style.maximumLineHeight = lineHeight
    style.lineBreakMode = .byWordWrapping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: style
    ]
    NSString(string: value).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                 attributes: attributes)
}

private func drawPlaceholder(in rect: NSRect, label: String, accent: NSColor) {
    NSColor(calibratedWhite: 0.975, alpha: 1).setFill()
    rect.fill()

    let titleBar = NSRect(x: rect.minX, y: rect.maxY - 76, width: rect.width, height: 76)
    NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
    titleBar.fill()
    for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        color.withAlphaComponent(0.78).setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.minX + 30 + CGFloat(index) * 38,
                                    y: titleBar.midY - 10, width: 20, height: 20)).fill()
    }

    let sidebar = NSRect(x: rect.minX, y: rect.minY, width: 260, height: rect.height - 76)
    NSColor(calibratedWhite: 0.945, alpha: 1).setFill()
    sidebar.fill()
    for row in 0..<6 {
        let rowRect = NSRect(x: sidebar.minX + 28,
                             y: sidebar.maxY - 96 - CGFloat(row) * 112,
                             width: 204, height: 76)
        (row == 2 ? accent.withAlphaComponent(0.2) : NSColor.white).setFill()
        NSBezierPath(roundedRect: rowRect, xRadius: 10, yRadius: 10).fill()
    }

    let page = NSRect(x: sidebar.maxX + 150, y: rect.minY + 150,
                      width: rect.width - sidebar.width - 300, height: rect.height - 376)
    NSColor.white.setFill()
    let pagePath = NSBezierPath(roundedRect: page, xRadius: 8, yRadius: 8)
    pagePath.fill()
    accent.withAlphaComponent(0.72).setFill()
    NSBezierPath(roundedRect: page.insetBy(dx: 54, dy: 54), xRadius: 5, yRadius: 5).fill()
    drawText("APP VIEW PLACEHOLDER\n\(label)", in: page.insetBy(dx: 80, dy: 110),
             font: .systemFont(ofSize: 34, weight: .semibold), color: .white,
             lineHeight: 48, alignment: .center)
}

private func drawAppImage(_ imageURL: URL, in rect: NSRect, label: String, accent: NSColor) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 44
    shadow.shadowOffset = NSSize(width: 0, height: -24)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    let path = NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28)
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    if let image = NSImage(contentsOf: imageURL) {
        let sourceSize = image.size
        let scale = min(rect.width / sourceSize.width, rect.height / sourceSize.height)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let destination = NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                 width: size.width, height: size.height)
        image.draw(in: destination, from: .zero, operation: .copy, fraction: 1)
    } else {
        drawPlaceholder(in: rect, label: label, accent: accent)
    }
    NSGraphicsContext.restoreGraphicsState()

    NSColor.black.withAlphaComponent(0.12).setStroke()
    path.lineWidth = 2
    path.stroke()
}

private func render(template: Template, copy: CopyFile.Entry, raw: URL, output: URL) throws {
    guard template.background.count == 2 else { throw RenderError.invalidTemplate(template.id) }
    let start = try NSColor(hex: template.background[0])
    let end = try NSColor(hex: template.background[1])
    let accent = try NSColor(hex: template.accent)
    let primaryText = try NSColor(hex: "#201D1B")
    let secondaryText = try NSColor(hex: "#514B47")
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width),
                                        pixelsHigh: Int(canvas.height), bitsPerSample: 8,
                                        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw RenderError.cannotWrite(output.path)
    }
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSGradient(starting: start, ending: end)?.draw(in: NSRect(origin: .zero, size: canvas), angle: -28)

    // Keep the complete 16:10 app window inside the final image. Earlier
    // compositions intentionally bled it past the canvas edge, which hid the
    // sidebar/tray and made modal screenshots difficult to read.
    let appWidth: CGFloat = 1580
    let appHeight: CGFloat = 988
    let appX: CGFloat = template.layout == "left" ? 100 : 1200
    let appRect = topRect(x: appX, y: 406, width: appWidth, height: appHeight)
    drawAppImage(raw.appendingPathComponent(template.source), in: appRect,
                 label: template.id, accent: accent)

    let copyX: CGFloat = template.layout == "left" ? 1780 : 170
    let copyWidth: CGFloat = 900
    let alignment: NSTextAlignment = template.layout == "left" ? .left : .left
    accent.setFill()
    NSBezierPath(roundedRect: topRect(x: copyX, y: 470, width: 96, height: 12),
                 xRadius: 6, yRadius: 6).fill()
    drawText(copy.headline, in: topRect(x: copyX, y: 530, width: copyWidth, height: 440),
             font: .systemFont(ofSize: 104, weight: .bold), color: primaryText,
             lineHeight: 112, alignment: alignment)
    drawText(copy.subtext, in: topRect(x: copyX, y: 1050, width: copyWidth, height: 300),
             font: .systemFont(ofSize: 43, weight: .regular), color: secondaryText,
             lineHeight: 59, alignment: alignment)
    drawText("PHOTOBOOKS", in: topRect(x: copyX, y: 1510, width: copyWidth, height: 70),
             font: .systemFont(ofSize: 28, weight: .semibold), color: accent,
             lineHeight: 38, alignment: alignment)

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw RenderError.cannotWrite(output.path)
    }
    try FileManager.default.createDirectory(at: output.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try data.write(to: output)
}

do {
    guard let templatesPath = argument("--templates"), let copyPath = argument("--copy"),
          let rawPath = argument("--raw"), let outputPath = argument("--output") else {
        throw RenderError.usage
    }
    let decoder = JSONDecoder()
    let copy = try decoder.decode(CopyFile.self, from: Data(contentsOf: URL(fileURLWithPath: copyPath)))
    let templatesURL = URL(fileURLWithPath: templatesPath, isDirectory: true)
    let templateURLs = try FileManager.default.contentsOfDirectory(at: templatesURL,
                                                                   includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard templateURLs.count == 10 else {
        throw RenderError.invalidTemplate("expected 10 JSON files, found \(templateURLs.count)")
    }
    let rawURL = URL(fileURLWithPath: rawPath, isDirectory: true)
    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
    for templateURL in templateURLs {
        let template = try decoder.decode(Template.self, from: Data(contentsOf: templateURL))
        guard let entry = copy.screenshots[template.id] else { throw RenderError.missingCopy(template.id) }
        let destination = outputURL.appendingPathComponent("\(template.id).png")
        try render(template: template, copy: entry, raw: rawURL, output: destination)
        print("rendered \(destination.path)")
    }
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
