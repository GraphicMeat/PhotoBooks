import AppSupport
import EditCore
import ModelLayer
import PhotoBookCore
import SwiftUI

/// Zone-bound text editing: a draft `StyledText` plus the style bar
/// (font / size in real print points / color / alignment — D13). Done
/// commits through the editor model, which locks the slot. Presented as a
/// sheet by the browser for the model's `textEditingContext`.
struct TextEditorOverlay: View {
    let context: TextEditorContext
    let trimHeightInches: Double

    @Environment(BookEditorModel.self) private var editor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.self) private var environment

    @State private var draft: StyledText

    init(context: TextEditorContext, trimHeightInches: Double) {
        self.context = context
        self.trimHeightInches = trimHeightInches
        _draft = State(initialValue: context.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField(String(localized: "Caption", bundle: .module), text: $draft.string, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .accessibilityIdentifier("text-editor-field")

            styleBar

            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("text-editor-cancel")
                Button(String(localized: "Done", bundle: .module)) {
                    editor.commitText(slotID: context.slotID, text: draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .help(Text("Save this caption to the frame", bundle: .module))
                .accessibilityIdentifier("text-editor-done")
            }
        }
        .padding()
        .frame(minWidth: 460)
    }

    private var styleBar: some View {
        HStack(spacing: 16) {
            Picker(String(localized: "Font", bundle: .module), selection: $draft.fontName) {
                Text("Book Default", bundle: .module).tag("")
                ForEach(FontCatalog.families()) { family in
                    Text(family.displayName).tag(family.postScriptName)
                }
            }
            .frame(maxWidth: 200)
            .help(Text("Choose the typeface for this text", bundle: .module))
            .accessibilityIdentifier("text-editor-font")

            // 0.005-factor steps, DISPLAYED as print points on the current
            // trim height (D13: 7 in trim → 0.05 shows as 25.2 pt).
            Stepper {
                Text(verbatim: displayPoints(pointSizeFactor: draft.pointSizeFactor, trimHeightInches: trimHeightInches)
                    .formatted(.number.precision(.fractionLength(1))) + " pt")
                    .monospacedDigit()
            } onIncrement: {
                draft.pointSizeFactor = min(0.2, draft.pointSizeFactor + 0.005)
            } onDecrement: {
                draft.pointSizeFactor = max(0.005, draft.pointSizeFactor - 0.005)
            }
            .help(Text("Adjust the text size (shown in print points)", bundle: .module))
            .accessibilityIdentifier("text-editor-size")

            ColorPicker(String(localized: "Color", bundle: .module), selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .help(Text("Set the text color", bundle: .module))
                .accessibilityIdentifier("text-editor-color")

            Picker(String(localized: "Alignment", bundle: .module), selection: $draft.alignment) {
                Image(systemName: "text.alignleft").tag(PhotoBookCore.TextAlignment.leading)
                Image(systemName: "text.aligncenter").tag(PhotoBookCore.TextAlignment.center)
                Image(systemName: "text.alignright").tag(PhotoBookCore.TextAlignment.trailing)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 140)
            .help(Text("Align the text left, center, or right", bundle: .module))
            .accessibilityIdentifier("text-editor-alignment")
        }
    }

    /// SwiftUI `Color` ↔ model "#RRGGBB" bridge (AppColorHex, round-trip
    /// tested). Resolving through the environment turns any picked color
    /// into concrete sRGB components.
    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                let c = AppColorHex.components(draft.colorHex) ?? (red: 0, green: 0, blue: 0)
                return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
            },
            set: { newColor in
                let resolved = newColor.resolve(in: environment)
                draft.colorHex = AppColorHex.hex(red: Double(resolved.red),
                                                  green: Double(resolved.green),
                                                  blue: Double(resolved.blue))
            }
        )
    }
}
