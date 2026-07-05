import Foundation

/// Filenames for exported PDFs. Blurb's two-file convention (D11):
/// `<Title>-interior.pdf` + `<Title>-cover.pdf` in a user-picked folder.
public enum ExportFilenames {

    /// Filesystem-safe variant of the book title: path separators and
    /// colons become dashes, surrounding whitespace is trimmed, and an
    /// empty result falls back to "Photo Book".
    public static func sanitized(title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = String(trimmed.map { character -> Character in
            character == "/" || character == ":" || character == "\\" ? "-" : character
        })
        return safe.isEmpty ? "Photo Book" : safe
    }

    public static func interior(title: String) -> String { "\(sanitized(title: title))-interior.pdf" }
    public static func cover(title: String) -> String { "\(sanitized(title: title))-cover.pdf" }
    public static func single(title: String) -> String { "\(sanitized(title: title)).pdf" }
}
