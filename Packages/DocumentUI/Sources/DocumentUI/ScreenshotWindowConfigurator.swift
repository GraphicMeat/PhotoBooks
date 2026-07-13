#if os(macOS) && DEBUG
import AppKit
import SwiftUI

/// Makes App Store screenshot captures deterministic without changing normal
/// app windows. `-ScreenshotMode YES` fixes the content area at 1440 x 900
/// points and forces light appearance; on a Retina display that is the App
/// Store's accepted 2880 x 1800 pixel size.
struct ScreenshotWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        guard UserDefaults.standard.bool(forKey: "ScreenshotMode") else { return view }
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard UserDefaults.standard.bool(forKey: "ScreenshotMode") else { return }
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.center()
        window.titleVisibility = .visible
    }
}
#endif
