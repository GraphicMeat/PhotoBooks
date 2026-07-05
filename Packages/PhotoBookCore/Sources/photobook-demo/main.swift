import Foundation
import ImageIO
import PhotoBookCore

// photobook-demo: reads a folder of images, extracts pixel dimensions and
// EXIF capture dates via CGImageSource, runs BookEngine.makeBook with the
// Blurb Standard Landscape preset, and prints a per-page summary.
//
// The PhotoBookCore LIBRARY stays Foundation-only; ImageIO is allowed here
// because this is an executable demo target, not the library.

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("usage: photobook-demo <folder-of-images>")
    exit(64)    // EX_USAGE
}

let folderURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff"]

let contents: [URL]
do {
    contents = try FileManager.default.contentsOfDirectory(
        at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
} catch {
    print("error: cannot read folder \(folderURL.path): \(error.localizedDescription)")
    exit(66)    // EX_NOINPUT
}

// EXIF dates have no timezone; parse them as UTC with a fixed-format locale.
let exifFormatter = DateFormatter()
exifFormatter.locale = Locale(identifier: "en_US_POSIX")
exifFormatter.timeZone = TimeZone(secondsFromGMT: 0)
exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"

var photoRefs: [PhotoRef] = []
for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
where imageExtensions.contains(url.pathExtension.lowercased()) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        print("skipping unreadable image: \(url.lastPathComponent)")
        continue
    }

    // Normalize EXIF rotation: orientations 5–8 are 90°/270° rotations, so
    // the stored pixel dimensions are swapped relative to display.
    var pixelWidth = width
    var pixelHeight = height
    if let rawOrientation = properties[kCGImagePropertyOrientation] as? UInt32,
       (5...8).contains(rawOrientation) {
        swap(&pixelWidth, &pixelHeight)
    }

    var captureDate: Date? = nil
    if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
       let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
        captureDate = exifFormatter.date(from: dateString)
    }

    photoRefs.append(PhotoRef(
        id: PhotoID(rawValue: url.lastPathComponent),
        source: .file(bookmark: url.dataRepresentation),
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        captureDate: captureDate))
}

guard !photoRefs.isEmpty else {
    print("no readable images found in \(folderURL.path)")
    exit(66)    // EX_NOINPUT
}
guard let preset = PresetLibrary.preset(id: "blurb-standard-landscape") else {
    print("error: blurb-standard-landscape preset missing from PresetLibrary")
    exit(70)    // EX_SOFTWARE
}

let book = BookEngine().makeBook(
    title: folderURL.lastPathComponent,
    photos: photoRefs,
    preset: preset,
    style: .standard,
    seed: 0xB00C)

print("Book \"\(book.title)\" — \(book.pages.count) pages, \(book.photoLibrary.count) photos")
for (index, page) in book.pages.enumerated() {
    let originKind: String
    switch page.origin {
    case .template(let id):
        originKind = "template(\(id))"
    case .generated(let params):
        originKind = "generated(seed: \(params.seed))"
    }
    let photoIDs = page.photoSlots.compactMap { $0.photoID?.rawValue }.joined(separator: ", ")
    print("page \(index) [\(page.role.rawValue)] \(originKind) — \(page.photoSlots.count) slots: \(photoIDs)")
}
