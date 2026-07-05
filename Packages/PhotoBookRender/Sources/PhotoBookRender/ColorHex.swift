import SwiftUI

/// Parses the model's "#RRGGBB" color strings. Pure function — unit-tested
/// with golden values; the `Color` initializer below is the only SwiftUI
/// touchpoint.
enum ColorHex {

    /// Accepts "#RRGGBB" or "RRGGBB" (case-insensitive). Invalid input
    /// falls back to opaque black — the model is expected to carry
    /// well-formed hex, so this is defensive, not a feature.
    static func components(_ hex: String) -> (red: Double, green: Double, blue: Double) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else {
            return (0, 0, 0)
        }
        return (
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

extension Color {
    /// sRGB color from a model hex string ("#RRGGBB").
    init(hex: String) {
        let c = ColorHex.components(hex)
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: 1)
    }
}
