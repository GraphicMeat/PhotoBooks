import AppSupport
import SwiftUI
import ModelLayer

#if os(macOS)
import AppKit

/// macOS launch/reopen policy for the document app. Without this, the
/// system `NSDocumentController` shows an Open panel at launch and a dead
/// menu-bar app after the last window closes — both bypass our
/// `WelcomeView`. This delegate makes launch and reopen create a NEW empty
/// document (which routes to `WelcomeView`) instead.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // Launch with a fresh untitled document rather than the app-centric
        // Open panel, so the first thing the user sees is the welcome screen.
        UserDefaults.standard.register(
            defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
        #if DEBUG
        // UITests start from a known state: `-resetSupporterStatus YES`.
        if UserDefaults.standard.bool(forKey: "resetSupporterStatus") {
            UserDefaults.standard.removeObject(forKey: SupporterStatus.defaultsKey)
        }
        #endif
        // An Apple Event handler, not `.onOpenURL`: Stripe's return link must
        // count even when no document window is open to receive it. Only the
        // Developer ID build registers the scheme.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleOpenURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleOpenURL(_ event: NSAppleEventDescriptor,
                                     withReplyEvent reply: NSAppleEventDescriptor) {
        guard let link = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: link) else { return }
        SupporterStatus.handle(url)
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    /// Clicking the Dock icon / reactivating with no windows open (e.g. after
    /// closing the last window) creates a new document so the welcome screen
    /// returns, instead of leaving a windowless, stuck app.
    public func applicationShouldHandleReopen(_ sender: NSApplication,
                                              hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NSDocumentController.shared.newDocument(nil)
        }
        return true
    }
}
#endif

extension BookDocument {
    /// Factory for NEW documents. In DEBUG builds the
    /// `-newBookFromFixtureFolder <path>` launch argument makes every new
    /// document open as a deterministic generated book (UITest smoke path);
    /// otherwise a new document starts empty and shows the setup flow.
    public static func makeNewDocument() -> BookDocument {
        #if DEBUG
        if let folder = DebugFixtureBook.fixtureFolderFromLaunchArguments {
            return BookDocument(book: DebugFixtureBook.makeBook(fixtureFolder: folder))
        }
        #endif
        return BookDocument()
    }
}
