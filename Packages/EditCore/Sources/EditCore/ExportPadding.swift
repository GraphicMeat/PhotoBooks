import Foundation
import PhotoBookCore

/// Blank-pad mutation for the preflight page-count offer (spec: "offer
/// blank-pad or reshuffle"). Pure static mutation in the `EditMutations`
/// style; applied through the document funnel so it is undoable.
public enum ExportPadding {

    /// Appends empty standard pages (background only, no slots) until the
    /// book reaches the preset's minimum. No-op at or above the minimum.
    public static func padToMinimum(in book: inout Book, preset: PrintPreset) {
        var standardCount = book.pages.count(where: { $0.role == .standard })
        while standardCount < preset.minPages {
            book.pages.append(Page(id: UUID(), role: .standard,
                                   origin: .template(id: "blank"),
                                   photoSlots: [], textSlots: [], isLocked: false))
            standardCount += 1
        }
    }
}
