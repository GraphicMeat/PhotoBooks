import ModelLayer
import PhotoBookCore
import SwiftUI

/// "Book Format…" sheet: switch the book's print preset after creation
/// (spec "Preset switch after creation"). Reuses the setup flow's preset
/// cards (Plan 4, NewBookSetupView step 2) with the book's current preset
/// highlighted. Same aspect class → instant; cross-class → relayout with
/// review flags (see `BookEditorModel.changePreset`).
public struct PresetPickerView: View {
    @Environment(BookEditorModel.self) private var editor
    @Environment(\.dismiss) private var dismiss

    public init() {}

    /// On open a `.sheet` auto-focuses its first focusable control — here the
    /// first preset card — drawing a system focus ring that reads as a stray
    /// selection. Park initial focus on Cancel so no card looks pre-selected;
    /// Tab still reaches the cards.
    private enum Focus: Hashable { case cancel }
    @FocusState private var focus: Focus?

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Book Format", bundle: .module).font(.title2)
            Text("Switching to a different shape relays out unlocked pages; locked pages and the cover keep their layout and get a review badge.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                ForEach([AspectClass.square, .landscape, .portrait], id: \.rawValue) { aspectClass in
                    let presets = PresetLibrary.all().filter { $0.aspectClass == aspectClass }
                    if !presets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(aspectClass.displayTitle)
                                .font(.headline)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                                alignment: .leading,
                                spacing: 12
                            ) {
                                ForEach(presets) { preset in
                                    Button {
                                        editor.changePreset(to: preset)
                                        dismiss()
                                    } label: {
                                        PresetCard(preset: preset, isCurrent: preset.id == editor.preset.id)
                                    }
                                    .buttonStyle(.plain)
                                    .focusEffectDisabled()
                                    .disabled(preset.id == editor.preset.id)
                                    .help(preset.id == editor.preset.id
                                          ? Text("Current format", bundle: .module)
                                          : Text("Switch the book to this format", bundle: .module))
                                    .accessibilityIdentifier("format-preset-\(preset.id)")
                                }
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                    .focused($focus, equals: .cancel)
                    .accessibilityIdentifier("format-cancel")
            }
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 380)
        #endif
        .defaultFocus($focus, .cancel)
    }

}
