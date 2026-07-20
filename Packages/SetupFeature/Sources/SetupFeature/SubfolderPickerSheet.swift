import PhotoBookImport
import SwiftUI

/// Shown after picking an import folder that contains subfolders with
/// photos: choose which folders to import from. Each row is one folder's
/// direct files; all rows start checked.
struct SubfolderPickerSheet: View {
    @Bindable var model: SubfolderSelectionModel
    let rootTitle: String
    let onCancel: () -> Void
    let onImport: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Folders in “\(rootTitle)”", bundle: .module)
                    .font(.headline)
                Spacer()
                Button {
                    model.toggleAll()
                } label: {
                    model.allSelected
                        ? Text("Deselect All", bundle: .module)
                        : Text("Select All", bundle: .module)
                }
                .buttonStyle(.borderless)
                .help(Text("Check or uncheck every folder at once", bundle: .module))
                .accessibilityIdentifier("subfolders-toggle-all")
            }
            .padding()

            List(model.folders, id: \.url) { folder in
                Toggle(isOn: Binding(
                    get: { model.isChecked(folder) },
                    set: { model.setChecked(folder, $0) }
                )) {
                    HStack {
                        folder.relativePath.isEmpty
                            ? Text("Top level", bundle: .module)
                            : Text(folder.relativePath)
                        Spacer()
                        Text(folder.imageCount, format: .number)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier("subfolder-row-\(folder.relativePath)")
            }

            Divider()
            HStack {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel", bundle: .module)
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    onImport(model.selectedURLs)
                } label: {
                    Text("Import \(model.selectedCount) Photos", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedCount == 0)
                .help(Text("Import photos from the checked folders", bundle: .module))
                .accessibilityIdentifier("subfolders-import")
            }
            .padding()
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
    }
}
