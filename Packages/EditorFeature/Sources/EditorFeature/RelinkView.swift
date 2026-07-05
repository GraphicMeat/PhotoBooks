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
            Text("Missing Photos")
                .font(.title2)
            Text("These photos can't be found. Pick the folder they moved to, or remove them from the book.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List(missingRefs) { ref in
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MissingPhotoSweep.rememberedFilename(for: ref) ?? ref.id.rawValue)
                            .lineLimit(1)
                        Text(isFileSource(ref)
                             ? "File moved or deleted — relink by picking its folder."
                             : "Deleted from your Photos library — relinking isn't possible.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove from Book", role: .destructive) {
                        if isFileSource(ref) {
                            editor.removeMissingPhoto(ref.id)
                        } else {
                            pendingRemoval = ref   // PhotoKit: explain first
                        }
                    }
                    .help("Remove this missing photo and clear its frames")
                }
            }
            .frame(minHeight: 160)

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .accessibilityIdentifier("relink-status")
            }

            HStack {
                Button("Relink from Folder…") { showFolderImporter = true }
                    .disabled(!missingRefs.contains(where: isFileSource))
                    .help("Point PhotoBooks at the folder these photos moved to")
                    .accessibilityIdentifier("relink-choose-folder")
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .help("Close this dialog")
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
                ? "No files in that folder match the missing photos' names."
                : "Relinked \(relinked) photo\(relinked == 1 ? "" : "s")."
        }
        .alert("Photo Deleted from Photos",
               isPresented: Binding(get: { pendingRemoval != nil },
                                    set: { if !$0 { pendingRemoval = nil } }),
               presenting: pendingRemoval) { ref in
            Button("Remove from Book", role: .destructive) {
                editor.removeMissingPhoto(ref.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This photo was deleted from your Photos library, so it can't be relinked. Removing it clears its frames; they can be refilled from the tray or by reshuffling.")
        }
    }
}
