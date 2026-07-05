import CryptoKit
import Foundation
import ImageIO
import PhotoBookCore

/// ImageIO-based metadata extraction: pixel dimensions (orientation-applied),
/// EXIF capture date, and a stable deterministic `PhotoID`.
///
/// The engine never sees EXIF rotation: `pixelWidth`/`pixelHeight` are
/// *display* dimensions (EXIF orientations 5–8 transpose, so stored width
/// and height are swapped).
public enum MetadataReader {

    /// Builds a `PhotoRef` for the image file at `url`. `bookmark` is the
    /// already-created security-scoped bookmark for the file; it is stored
    /// verbatim in `PhotoSource.file(bookmark:)`.
    ///
    /// Throws `PhotoProviderError.assetUnavailable` if the file is missing,
    /// unreadable, or not a decodable image.
    public static func photoRef(forFileAt url: URL, bookmark: Data) throws -> PhotoRef {
        let id = photoID(forFileAt: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let storedWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let storedHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw PhotoProviderError.assetUnavailable(id)
        }

        // EXIF orientation (CIPA DC-008): 1 = upright, 2–4 = flips/180°,
        // 5–8 = 90° transposes. Absent tag means 1.
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let swapsDimensions = (5...8).contains(orientation)

        return PhotoRef(
            id: id,
            source: .file(bookmark: bookmark),
            pixelWidth: swapsDimensions ? storedHeight : storedWidth,
            pixelHeight: swapsDimensions ? storedWidth : storedHeight,
            captureDate: captureDate(from: properties, fileURL: url),
            isMissing: false
        )
    }

    /// Stable deterministic file identity: SHA-256 of the URL's standardized
    /// path, first 16 hex characters. Same path → same ID, every run, every
    /// machine. (Renaming/moving a file changes its ID; the bookmark — not
    /// the ID — is what re-locates moved files, and re-imported files simply
    /// mint a fresh `PhotoRef`.)
    static func photoID(forFileAt url: URL) -> PhotoID {
        let path = url.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return PhotoID(rawValue: String(hex.prefix(16)))
    }

    /// Capture-date fallback chain:
    /// EXIF `DateTimeOriginal` → TIFF `DateTime` → file creation date → nil.
    static func captureDate(from properties: [CFString: Any], fileURL: URL) -> Date? {
        let formatter = makeEXIFDateFormatter()
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = formatter.date(from: raw) {
            return date
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let raw = tiff[kCGImagePropertyTIFFDateTime] as? String,
           let date = formatter.date(from: raw) {
            return date
        }
        if let creationDate = (try? fileURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate {
            return creationDate
        }
        return nil
    }

    /// EXIF date strings ("yyyy:MM:dd HH:mm:ss") carry no time zone. We pin
    /// UTC so the parsed `Date` is machine-independent — capture dates only
    /// drive relative ordering and time-gap clustering, where a constant
    /// offset is harmless. `en_US_POSIX` guards against user-locale calendar
    /// and digit weirdness. (`DateFormatter` is not Sendable under Swift 6,
    /// so we build one per call instead of caching a `static let`.)
    private static func makeEXIFDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }
}
