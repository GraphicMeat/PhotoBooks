import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shown when Photos access is denied or restricted (spec error handling:
/// "Photos permission denied/limited → explainer + Settings deep-link;
/// limited mode functional"). Explains why access is needed, deep-links to
/// the right Settings pane per platform, and offers the folder source as
/// an escape hatch — the app stays fully usable without Photos access.
struct PermissionExplainerView: View {
    /// Escape hatch: switch the setup flow to the folder source.
    let onUseFolder: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("PhotoBooks Can't See Your Photos", bundle: .module)
                .font(.title2)
            Text("PhotoBooks lays out books from photos you pick in your library. Access is currently denied — you can grant it in Settings, or build your book from a folder instead.", bundle: .module)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 12) {
                Button(String(localized: "Open Settings", bundle: .module)) { openPhotosSettings() }
                    .buttonStyle(.borderedProminent)
                    .help(Text("Open System Settings to grant Photos access", bundle: .module))
                    .accessibilityIdentifier("permission-open-settings")
                Button(String(localized: "Use Folder Instead", bundle: .module)) { onUseFolder() }
                    .help(Text("Build your book from a folder instead of Photos", bundle: .module))
                    .accessibilityIdentifier("permission-use-folder")
            }
        }
        .padding(40)
    }

    /// The Settings deep-link, per platform (spec: "explainer + Settings
    /// deep-link").
    private func openPhotosSettings() {
        #if os(macOS)
        // System Settings → Privacy & Security → Photos.
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
        #else
        // The app's own Settings page — the only sanctioned deep-link on iOS.
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
