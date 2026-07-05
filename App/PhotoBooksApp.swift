import DocumentUI
import ExportFeature
import ModelLayer
import SwiftUI

@main
struct PhotoBooksApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        DocumentGroup(newDocument: { BookDocument.makeNewDocument() }) { configuration in
            ContentView(document: configuration.document)
        }
        .commands { ExportCommands() }
    }
}
