import ModelLayer
import PhotoBookCore
import SwiftUI
import UniformTypeIdentifiers

/// First screen of an empty document window: a clear chooser between starting
/// a new book and opening an existing `.photobook`. "Create" hands control to
/// the existing setup flow via `onCreate`. The "Open Existing Project…"
/// affordance is macOS-only — programmatic document opening
/// (`@Environment(\.openDocument)`) is unavailable on iOS, where the system
/// `DocumentGroup` file browser is the entry point for opening saved books.
struct WelcomeView: View {
    let onCreate: () -> Void

    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    @State private var showOpenImporter = false
    @State private var errorMessage: String?
    #endif

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Create a Photo Book")
                    .font(.largeTitle.bold())
                Text("Where are your photos?")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button(action: onCreate) {
                Label("Choose Photos…", systemImage: "photo.on.rectangle.angled")
                    .font(.title3)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Start a new book from photos in your library or a folder")
            .accessibilityIdentifier("welcome-create")

            #if os(macOS)
            Button {
                showOpenImporter = true
            } label: {
                Label("Open Existing Project…", systemImage: "folder")
                    .font(.title3)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Open a saved PhotoBooks project")
            .accessibilityIdentifier("welcome-open")

            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
            #endif
        }
        .padding(40)
        .frame(minWidth: 480, minHeight: 420)
        #if os(macOS)
        .fileImporter(isPresented: $showOpenImporter,
                      allowedContentTypes: [.photoBook]) { result in
            switch result {
            case .success(let url):
                openProject(at: url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        #endif
    }

    #if os(macOS)
    private func openProject(at url: URL) {
        errorMessage = nil
        let scoped = url.startAccessingSecurityScopedResource()
        Task {
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try await openDocument(at: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    #endif
}
