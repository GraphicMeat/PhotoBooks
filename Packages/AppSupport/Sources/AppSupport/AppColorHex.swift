import Foundation

/// Two-way "#RRGGBB" ↔ sRGB component bridge for the app's color editing.
/// (The render package's `ColorHex` is internal there and parse-only.)
/// Round-trip is exact for every byte value — golden-tested.
public enum AppColorHex {

    /// "#RRGGBB" or "RRGGBB", case-insensitive. `nil` for malformed input
    /// (callers fall back to black).
    public static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        return (
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }

    /// Components (clamped to 0…1) → "#RRGGBB", uppercase.
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }
}
