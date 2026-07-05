import Foundation
import PhotoBookCore
import PhotoBookRender

/// Pure display logic over `[PreflightIssue]`: blocking state, the
/// sidebar's per-page warning badge set, and human-readable row content.
public struct PreflightSummary: Equatable {
    var issues: [PreflightIssue]

    public var hasBlockingIssues: Bool { issues.contains(where: \.isBlocking) }

    /// Page indexes (into `book.pages`) carrying at least one NON-blocking
    /// warning — the sidebar badge set. Blocking issues already surface
    /// through Plan 5's missing-photo banner and block the export flow.
    var pageIndexesWithWarnings: Set<Int> {
        Set(issues.filter { !$0.isBlocking }.compactMap(\.pageIndex))
    }

    public static func message(for issue: PreflightIssue) -> String {
        switch issue.kind {
        case .missingPhoto:
            "A photo is missing — relink or remove it before exporting."
        case .lowResolution(_, let effectiveDPI):
            "A photo prints at \(effectiveDPI) DPI, below the 200 DPI threshold."
        case .pageCountOutOfRange(let actual, let min, let max):
            "The book has \(actual) pages; this preset prints \(min)–\(max)."
        case .textOverflow:
            "Text does not fit its zone and will be cut off."
        }
    }

    public static func systemImage(for issue: PreflightIssue) -> String {
        issue.isBlocking ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"
    }
}
