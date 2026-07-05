import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Color {
    /// sRGB color from a model hex string ("#RRGGBB").
    /// Mirrors `PhotoBookRender.ColorHex` (which is internal) for use in the app target.
    public init(hex: String) {
        let c = AppColorHex.components(hex) ?? (red: 0, green: 0, blue: 0)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }

    /// "#RRGGBB" in sRGB for persisting a picked color into the model.
    public var rgbHexString: String {
        #if os(macOS)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
        #else
        // `UIColor.getRed` returns components in the receiver's NATIVE space
        // (Display-P3 on wide-gamut displays), not sRGB. Resolve to sRGB
        // explicitly. `Color.Resolved` (iOS 17+) carries gamma-encoded sRGB
        // components, extended past [0,1] for wide-gamut input — clamp before
        // quantizing to 8-bit hex.
        let resolved = resolve(in: EnvironmentValues())
        func channel(_ v: Float) -> Int { Int((Double(min(max(v, 0), 1)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X",
                      channel(resolved.red), channel(resolved.green), channel(resolved.blue))
        #endif
    }
}
