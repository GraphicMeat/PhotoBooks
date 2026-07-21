import PhotoBookCore
import PhotoBookImport
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Inline wizard step shown after picking an import folder that contains
/// subfolders with photos: choose which folders — and optionally which
/// photos — to import. Top: folder list with toggles. Bottom: preview grid
/// of the highlighted folder (same masonry + thumbnail treatment as the
/// curation review step), where individual photos can be deselected.
struct SubfolderPickerView: View {
    @Bindable var model: SubfolderSelectionModel
    let rootTitle: String
    let rootURL: URL
    let provider: FileSystemProvider
    let onImport: (_ folders: [URL], _ excluded: Set<PhotoID>) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
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
            .padding(.horizontal)
            .padding(.vertical, 8)

            List(model.folders, id: \.url) { folder in
                folderRow(folder)
                    .listRowBackground(
                        model.previewFolder == folder
                            ? Color.accentColor.opacity(0.12) : nil)
            }
            .frame(maxHeight: 220)

            Divider()
            previewPane
            Divider()

            HStack {
                Spacer()
                Button {
                    onImport(model.selectedURLs, model.excluded)
                } label: {
                    Text("Import \(model.selectedCount) Photos", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.selectedCount == 0)
                .help(Text("Import photos from the checked folders", bundle: .module))
                .accessibilityIdentifier("subfolders-import")
            }
            .padding()
        }
    }

    // MARK: - Rows

    private func title(for folder: FolderInfo) -> String {
        folder.relativePath.isEmpty ? rootTitle : folder.relativePath
    }

    @ViewBuilder
    private func folderRow(_ folder: FolderInfo) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { model.isChecked(folder) },
                set: { model.setChecked(folder, $0) }
            )) { EmptyView() }
            .labelsHidden()
            .help(Text("Include this folder's photos in the import", bundle: .module))

            Button {
                model.previewFolder = folder
            } label: {
                HStack {
                    Text(title(for: folder))
                        .lineLimit(1)
                    Spacer()
                    countLabel(folder)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Show this folder's photos below", bundle: .module))

            #if os(macOS)
            Button {
                NSWorkspace.shared.open(folder.url)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help(Text("Open this folder in Finder", bundle: .module))
            .accessibilityIdentifier("subfolder-finder-\(folder.relativePath)")
            #endif
        }
        .accessibilityIdentifier("subfolder-row-\(folder.relativePath)")
    }

    @ViewBuilder
    private func countLabel(_ folder: FolderInfo) -> some View {
        let selected = model.selectedCount(in: folder)
        Group {
            if model.isChecked(folder) && selected < folder.imageCount {
                Text(verbatim: "\(selected) / \(folder.imageCount)")
            } else {
                Text(folder.imageCount, format: .number)
            }
        }
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewPane: some View {
        if let folder = model.previewFolder {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title(for: folder))
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text("\(model.selectedCount(in: folder)) of \(folder.imageCount) selected", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding([.horizontal, .top])

                if let refs = model.refs(for: folder) {
                    // LazyVGrid + square cells, NOT the masonry Layout the
                    // curation step uses: Layout protocol instantiates every
                    // subview eagerly — thousands of cells for a big folder —
                    // while the lazy grid only builds what scrolls into view,
                    // so thumbnail decodes fire per visible cell.
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 180), spacing: 10)],
                                  spacing: 10) {
                            ForEach(refs, id: \.id) { ref in
                                ProviderThumbnailCell(
                                    ref: ref, provider: provider,
                                    isSelected: model.isPhotoSelected(ref, in: folder),
                                    square: true
                                ) {
                                    model.togglePhoto(ref.id, in: folder)
                                }
                            }
                        }
                        .padding([.horizontal, .bottom])
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task(id: folder.url) {
                            let refs = (try? await provider.photoRefs(
                                inFolders: [folder.url], root: rootURL)) ?? []
                            model.setRefs(refs, for: folder.url)
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Spacer(minLength: 0)
        }
    }
}
