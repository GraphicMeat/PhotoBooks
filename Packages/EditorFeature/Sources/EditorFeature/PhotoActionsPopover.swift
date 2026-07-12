import SwiftUI
import ModelLayer

/// The action row shown in a popover over the selected photo slot.
struct PhotoActionsPopover: View {
    @Bindable var editor: BookEditorModel
    let slotIsLocked: Bool
    let pageIsLocked: Bool

    var body: some View {
        HStack(spacing: 4) {
            button("Adjust photo", systemImage: "crop",
                   help: "Zoom and position this photo (or double-click the photo)",
                   id: "photo-action-crop") {
                editor.beginCropEditingSelectedPhoto()
            }
            button("Replace", systemImage: "arrow.triangle.2.circlepath",
                   help: "Replace this photo — then tap another photo or a tray photo to swap it in",
                   id: "photo-action-replace") {
                editor.beginReplaceSelectedPhoto()
            }
            button("More", systemImage: "plus.rectangle",
                   help: "Add a photo to this page (pulled from the next page)",
                   id: "photo-action-bigger",
                   disabled: !editor.canIncreaseSelectedPageDensity) {
                editor.increaseSelectedPageDensity()
            }
            button("Fewer", systemImage: "minus.rectangle",
                   help: "Remove a photo from this page (moved to the next page)",
                   id: "photo-action-smaller",
                   disabled: !editor.canDecreaseSelectedPageDensity) {
                editor.decreaseSelectedPageDensity()
            }
            button("Make key", systemImage: "star",
                   help: "Emphasize this photo — shrink surrounding photos so it stands out",
                   id: "photo-action-key",
                   disabled: !editor.selectedPhotoCanGrow || slotIsLocked) {
                editor.makeSelectedPhotoKey()
            }
            button("Reset to auto layout", systemImage: "arrow.uturn.backward",
                   help: "Return this photo to automatic placement on its page",
                   id: "photo-action-reset",
                   disabled: !slotIsLocked) {
                editor.resetSelectedPhotoToAutoLayout()
            }
            Divider().frame(height: 20)
            // Photo lock: a plain padlock (locks just this one photo's frame).
            button(slotIsLocked ? "Unlock photo" : "Lock photo",
                   systemImage: slotIsLocked ? "lock.fill" : "lock.open",
                   help: slotIsLocked
                        ? "Photo is locked — click to unlock so reflow can move it"
                        : "Lock just this photo so reflow leaves it in place",
                   id: "photo-action-lock-slot") {
                editor.toggleSelectedSlotLock()
            }
            // Page lock: a padlock on a document (locks the whole page) — a
            // distinct glyph so it doesn't read as a second photo lock.
            button(pageIsLocked ? "Unlock page" : "Lock page",
                   systemImage: pageIsLocked ? "lock.doc.fill" : "lock.doc",
                   help: pageIsLocked
                        ? "Whole page is locked — click to unlock so reflow can re-lay it"
                        : "Lock the whole page so reflow skips every photo on it",
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
