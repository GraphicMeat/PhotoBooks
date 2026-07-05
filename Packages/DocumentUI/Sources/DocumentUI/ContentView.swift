import AppSupport
import EditorFeature
import ExportFeature
import ModelLayer
import PhotoBookCore
import PhotoBookImport
import SetupFeature
import SwiftUI

/// Per-document-window session state: providers + image store + editor
/// model. Lives in a `@StateObject` so the thumbnail cache and selection
/// survive view re-renders.
@MainActor
final class BookSession: ObservableObject {
    let providers: AppProviders
    let imageStore: AppImageStore
    let editor: BookEditorModel
    let exportModel: ExportModel

    init(document: BookDocument) {
        let providers = AppProviders()
        self.providers = providers
        // The refProvider closure reads the document's thread-safe ref
        // snapshot — NOT `document.book` directly, which is main-actor-only.
        let imageStore = AppImageStore(
            fileSystemProvider: providers.fileSystem,
            photoKitProvider: providers.photoKit,
            refProvider: { [weak document] in document?.refsByID ?? [:] }
        )
        self.imageStore = imageStore
        self.editor = BookEditorModel(document: document,
                                      photoKitProvider: providers.photoKit)
        self.exportModel = ExportModel(document: document, imageStore: imageStore)
    }
}

/// Document root: empty book → setup flow; populated book → browser.
public struct ContentView: View {
    @ObservedObject var document: BookDocument
    @StateObject private var session: BookSession

    @State private var isCreating = false

    public init(document: BookDocument) {
        self.document = document
        _session = StateObject(wrappedValue: BookSession(document: document))
    }

    public var body: some View {
        switch contentRoute(pagesEmpty: document.book.pages.isEmpty, isCreating: isCreating) {
        case .welcome:
            WelcomeView(onCreate: { isCreating = true })
        case .setup:
            NewBookSetupView(document: document, providers: session.providers,
                             onExitToWelcome: { isCreating = false })
        case .browser:
            BookBrowserView(document: document, imageStore: session.imageStore,
                            editor: session.editor, exportModel: session.exportModel)
        }
    }
}
