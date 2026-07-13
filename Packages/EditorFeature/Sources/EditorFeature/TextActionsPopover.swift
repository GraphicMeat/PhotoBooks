import PhotoBookRender
import SwiftUI
import ModelLayer

/// Action row over the selected text box: Edit, Lock/Unlock, Delete.
struct TextActionsPopover: View {
    @Bindable var editor: BookEditorModel

    var body: some View {
        HStack(spacing: 4) {
            button(String(localized: "Edit", bundle: .module), systemImage: "character.cursor.ibeam",
                   help: String(localized: "Edit this caption's text and style", bundle: .module),
                   id: "text-action-edit") {
                if let id = editor.selectedTextSlotID { editor.beginTextEditing(id) }
            }
            button(editor.selectedTextSlotIsLocked ? String(localized: "Unlock", bundle: .module) : String(localized: "Lock", bundle: .module),
                   systemImage: editor.selectedTextSlotIsLocked ? "lock.fill" : "lock.open",
                   help: editor.selectedTextSlotIsLocked
                        ? String(localized: "Unlock this text box", bundle: .module)
                        : String(localized: "Lock this text box in place", bundle: .module),
                   id: "text-action-lock") {
                editor.toggleSelectedTextSlotLock()
            }
            Divider().frame(height: 20)
            button(String(localized: "Delete", bundle: .module), systemImage: "trash",
                   help: String(localized: "Delete this text box", bundle: .module),
                   id: "text-action-delete") {
                editor.removeSelectedTextSlot()
            }
        }
        .padding(6)
        .labelStyle(.iconOnly)
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

/// Non-transient inline card over the selected text box (same rationale as
/// `PhotoActionsInlineOverlay`: NOT a `.popover`, so the move/resize handles
/// underneath stay draggable). Reuses `SelectedSlotBoundsKey`; only ever
/// active when a text slot is selected (photo selection is mutually exclusive).
struct TextActionsInlineOverlay: ViewModifier {
    let editor: BookEditorModel

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(SelectedSlotBoundsKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, editor.selectedTextSlotID != nil, !editor.isReplacing {
                    let rect = proxy[anchor]
                    let gap: CGFloat = 44
                    let placeAbove = rect.minY > 72
                    let centerY = placeAbove ? rect.minY - gap : rect.maxY + gap
                    TextActionsPopover(editor: editor)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                        .shadow(radius: 8, y: 2)
                        .fixedSize()
                        .position(x: rect.midX, y: centerY)
                        .accessibilityIdentifier("text-actions-popover")
                }
            }
        }
    }
}
