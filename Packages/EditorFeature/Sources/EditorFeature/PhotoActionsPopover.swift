import SwiftUI
import ModelLayer

/// The action row shown in a popover over the selected photo slot.
struct PhotoActionsPopover: View {
    @Bindable var editor: BookEditorModel
    let slotIsLocked: Bool
    let pageIsLocked: Bool

    var body: some View {
        HStack(spacing: 4) {
            button(String(localized: "Adjust photo", bundle: .module), systemImage: "crop",
                   help: String(localized: "Zoom and position this photo (or double-click the photo)", bundle: .module),
                   id: "photo-action-crop") {
                editor.beginCropEditingSelectedPhoto()
            }
            button(String(localized: "Replace", bundle: .module), systemImage: "arrow.triangle.2.circlepath",
                   help: String(localized: "Replace this photo — then tap another photo or a tray photo to swap it in", bundle: .module),
                   id: "photo-action-replace") {
                editor.beginReplaceSelectedPhoto()
            }
            button(String(localized: "More", bundle: .module), systemImage: "plus.rectangle",
                   help: String(localized: "Add a photo to this page (pulled from the next page)", bundle: .module),
                   id: "photo-action-bigger",
                   disabled: !editor.canIncreaseSelectedPageDensity) {
                editor.increaseSelectedPageDensity()
            }
            button(String(localized: "Fewer", bundle: .module), systemImage: "minus.rectangle",
                   help: String(localized: "Remove a photo from this page (moved to the next page)", bundle: .module),
                   id: "photo-action-smaller",
                   disabled: !editor.canDecreaseSelectedPageDensity) {
                editor.decreaseSelectedPageDensity()
            }
            button(String(localized: "Make key", bundle: .module), systemImage: "star",
                   help: String(localized: "Emphasize this photo — shrink surrounding photos so it stands out", bundle: .module),
                   id: "photo-action-key",
                   disabled: !editor.selectedPhotoCanGrow || slotIsLocked) {
                editor.makeSelectedPhotoKey()
            }
            button(String(localized: "Reset to auto layout", bundle: .module), systemImage: "arrow.uturn.backward",
                   help: String(localized: "Return this photo to automatic placement on its page", bundle: .module),
                   id: "photo-action-reset",
                   disabled: !slotIsLocked) {
                editor.resetSelectedPhotoToAutoLayout()
            }
            Divider().frame(height: 20)
            // Photo lock: a plain padlock (locks just this one photo's frame).
            button(slotIsLocked ? String(localized: "Unlock photo", bundle: .module) : String(localized: "Lock photo", bundle: .module),
                   systemImage: slotIsLocked ? "lock.fill" : "lock.open",
                   help: slotIsLocked
                        ? String(localized: "Photo is locked — click to unlock so reflow can move it", bundle: .module)
                        : String(localized: "Lock just this photo so reflow leaves it in place", bundle: .module),
                   id: "photo-action-lock-slot") {
                editor.toggleSelectedSlotLock()
            }
            // Page lock: a padlock on a document (locks the whole page) — a
            // distinct glyph so it doesn't read as a second photo lock.
            button(pageIsLocked ? String(localized: "Unlock page", bundle: .module) : String(localized: "Lock page", bundle: .module),
                   systemImage: pageIsLocked ? "lock.doc.fill" : "lock.doc",
                   help: pageIsLocked
                        ? String(localized: "Whole page is locked — click to unlock so reflow can re-lay it", bundle: .module)
                        : String(localized: "Lock the whole page so reflow skips every photo on it", bundle: .module),
                   id: "photo-action-lock-page") {
                editor.toggleSelectedPageLock()
            }
        }
        .padding(6)
        .labelStyle(.iconOnly)
        // Don't draw a keyboard-focus ring on the first button when the popover
        // opens — the row is pointer-driven, so a pre-highlighted button reads
        // as a spurious selection.
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func button(_ title: String, systemImage: String, help: String,
                        id: String, disabled: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(disabled)
        .help(help)
        .accessibilityIdentifier(id)
    }
}
