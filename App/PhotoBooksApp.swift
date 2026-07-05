import DocumentUI
import ExportFeature
import ModelLayer
import SwiftUI
#if SPARKLE
import Combine
import Sparkle
#endif

@main
struct PhotoBooksApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    #if SPARKLE
    // Owns the Sparkle updater for the Developer ID build. `startingUpdater: true`
    // begins background checks immediately; Sparkle shows first-launch consent
    // before enabling automatic checks. Absent entirely from the App Store build.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    var body: some Scene {
        DocumentGroup(newDocument: { BookDocument.makeNewDocument() }) { configuration in
            ContentView(document: configuration.document)
        }
        .commands {
            ExportCommands()
            #if SPARKLE
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            #endif
        }
    }
}

#if SPARKLE
/// Reflects `SPUUpdater.canCheckForUpdates` so the "Check for Updates…" menu
/// item disables itself while an update check is already in flight.
@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

/// The "Check for Updates…" menu item, wired to the Sparkle updater.
private struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
#endif
