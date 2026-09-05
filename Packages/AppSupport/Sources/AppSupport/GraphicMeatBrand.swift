import SwiftUI

/// Graphic Meat brand assets shared by every feature package (welcome screen,
/// export thank-you screen).
public enum GraphicMeatBrand {
    public static let websiteURL = URL(string: "https://graphicmeat.com")!

    /// `static let` (not a computed property): as a computed property this hit
    /// the disk and decoded on the main thread on every body evaluation, which
    /// stalled the welcome screen right after a new document is created.
    public static let logo: Image = {
        guard let url = Bundle.module.url(forResource: "GraphicMeatLogo", withExtension: "png") else {
            return Image(systemName: "globe")
        }
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return Image(systemName: "globe") }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(contentsOfFile: url.path) else { return Image(systemName: "globe") }
        return Image(uiImage: image)
        #endif
    }()
}

/// How this build asks for support after a successful export. The App Store
/// build ships a StoreKit tip jar; the Developer ID (Sparkle) build cannot use
/// in-app purchase, so it links out to a donate page instead.
public enum SupportOffer: Sendable, Equatable {
    case tipJar
    case donate(URL)
}

extension EnvironmentValues {
    /// Injected by the app root — SPM packages never see the `SPARKLE`
    /// compilation condition, so distribution flavor has to arrive this way.
    @Entry public var supportOffer: SupportOffer = .tipJar
}
