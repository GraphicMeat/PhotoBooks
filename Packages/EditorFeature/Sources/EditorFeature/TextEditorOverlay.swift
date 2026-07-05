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
            TextField("Caption", text: $draft.string, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .accessibilityIdentifier("text-editor-field")

            styleBar

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("text-editor-cancel")
                Button("Done") {
                    editor.commitText(slotID: context.slotID, text: draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .help("Save this caption to the frame")
                .accessibilityIdentifier("text-editor-done")
            }
        }
        .padding()
        .frame(minWidth: 460)
    }

    private var styleBar: some View {
        HStack(spacing: 16) {
            Picker("Font", selection: $draft.fontName) {
                Text("Book Default").tag("")
                ForEach(FontCatalog.families()) { family in
                    Text(family.displayName).tag(family.postScriptName)
                }
            }
            .frame(maxWidth: 200)
            .help("Choose the typeface for this text")
            .accessibilityIdentifier("text-editor-font")

            // 0.005-factor steps, DISPLAYED as print points on the current
            // trim height (D13: 7 in trim → 0.05 shows as 25.2 pt).
            Stepper {
                Text("\(displayPoints(pointSizeFactor: draft.pointSizeFactor, trimHeightInches: trimHeightInches), format: .number.precision(.fractionLength(1))) pt")
                    .monospacedDigit()
            } onIncrement: {
                draft.pointSizeFactor = min(0.2, draft.pointSizeFactor + 0.005)
            } onDecrement: {
                draft.pointSizeFactor = max(0.005, draft.pointSizeFactor - 0.005)
            }
            .help("Adjust the text size (shown in print points)")
            .accessibilityIdentifier("text-editor-size")

            ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .help("Set the text color")
                .accessibilityIdentifier("text-editor-color")

            Picker("Alignment", selection: $draft.alignment) {
                Image(systemName: "text.alignleft").tag(PhotoBookCore.TextAlignment.leading)
                Image(systemName: "text.aligncenter").tag(PhotoBookCore.TextAlignment.center)
                Image(systemName: "text.alignright").tag(PhotoBookCore.TextAlignment.trailing)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 140)
            .help("Align the text left, center, or right")
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
