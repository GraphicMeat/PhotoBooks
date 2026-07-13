import AppSupport
import EditCore
import ModelLayer
import PhotoBookCore
import SwiftUI

/// Missing-photo resolution sheet. File-sourced photos relink by picking a
/// folder (matched on filename); PhotoKit photos cannot be relinked (the
/// asset is gone from the library) — removing them from the book is offered
/// behind a confirmation alert. Takes its own `@ObservedObject` document so
/// the list live-updates as photos resolve (D11).
struct RelinkView: View {
    @ObservedObject var document: BookDocument
    @Environment(BookEditorModel.self) private var editor
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderImporter = false
    @State private var statusMessage: String?
    @State private var pendingRemoval: PhotoRef?

    private var missingRefs: [PhotoRef] { document.book.photoLibrary.filter(\.isMissing) }

    private func isFileSource(_ ref: PhotoRef) -> Bool {
        if case .file = ref.source { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Missing Photos", bundle: .module)
                .font(.title2)
            Text("These photos can't be found. Pick the folder they moved to, or remove them from the book.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)

            List(missingRefs) { ref in
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MissingPhotoSweep.rememberedFilename(for: ref) ?? ref.id.rawValue)
                            .lineLimit(1)
                        (isFileSource(ref)
                             ? Text("File moved or deleted — relink by picking its folder.", bundle: .module)
                             : Text("Deleted from your Photos library — relinking isn't possible.", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "Remove from Book", bundle: .module), role: .destructive) {
                        if isFileSource(ref) {
                            editor.removeMissingPhoto(ref.id)
                        } else {
                            pendingRemoval = ref   // PhotoKit: explain first
                        }
                    }
                    .help(Text("Remove this missing photo and clear its frames", bundle: .module))
                }
            }
            .frame(minHeight: 160)

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .accessibilityIdentifier("relink-status")
            }

            HStack {
                Button(String(localized: "Relink from Folder…", bundle: .module)) { showFolderImporter = true }
                    .disabled(!missingRefs.contains(where: isFileSource))
                    .help(Text("Point PhotoBooks at the folder these photos moved to", bundle: .module))
                    .accessibilityIdentifier("relink-choose-folder")
                Spacer()
                Button(String(localized: "Done", bundle: .module)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .help(Text("Close this dialog", bundle: .module))
                    .accessibilityIdentifier("relink-done")
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 340)
        .fileImporter(isPresented: $showFolderImporter,
                      allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }   // cancel = no-op
            let relinked = editor.relinkMissingPhotos(toFolder: url)
            statusMessage = relinked == 0
                ? String(localized: "No files in that folder match the missing photos' names.", bundle: .module)
                : String(localized: "Relinked \(relinked) photos.", bundle: .module)
        }
        .alert(String(localized: "Photo Deleted from Photos", bundle: .module),
               isPresented: Binding(get: { pendingRemoval != nil },
                                    set: { if !$0 { pendingRemoval = nil } }),
               presenting: pendingRemoval) { ref in
            Button(String(localized: "Remove from Book", bundle: .module), role: .destructive) {
                editor.removeMissingPhoto(ref.id)
            }
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
        } message: { _ in
            Text("This photo was deleted from your Photos library, so it can't be relinked. Removing it clears its frames; they can be refilled from the tray or by reshuffling.", bundle: .module)
        }
    }
}
