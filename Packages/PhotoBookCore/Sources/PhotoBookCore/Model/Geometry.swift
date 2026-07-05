import Foundation

/// Normalized rectangle in 0–1 page space — the single coordinate system
/// shared by the layout engine, the SwiftUI renderer, and the PDF renderer.
public struct NormRect: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = NormRect(x: 0, y: 0, width: 1, height: 1)

    /// Right edge (`x + width`) and bottom edge (`y + height`) in the same
    /// 0–1 space. Convenience for intersection/slicing math.
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    /// Width/height in page-relative terms. A `NormRect`'s true on-page
    /// aspect depends on the physical page size; helpers that need true
    /// aspect must combine this with `SizeInches.aspectRatio`.
    public var aspectRatio: Double { width / height }

    /// Shrinks the rect by `amount` on every edge. Width and height clamp
    /// at zero so over-insetting never produces negative sizes.
    public func inset(by amount: Double) -> NormRect {
        NormRect(
            x: x + amount,
            y: y + amount,
            width: max(0, width - 2 * amount),
            height: max(0, height - 2 * amount)
        )
    }
}

/// Physical size in inches.
public struct SizeInches: Codable, Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public var aspectRatio: Double { width / height }
}

public extension SizeInches {
    /// Exact centimetres-per-inch conversion factor.
    static let centimetersPerInch: Double = 2.54

    /// e.g. `"7×7 in"`. Whole numbers render without a decimal; fractional
    /// sizes (8.5) render with one decimal. Matches the label that previously
    /// lived in the preset-picker views.
    var inchLabel: String {
        "\(Self.formatInches(width))×\(Self.formatInches(height)) in"
    }

    /// e.g. `"18×18 cm"`. Each dimension is rounded to the nearest whole
    /// centimetre, which reproduces the Blurb/BookWright catalog values
    /// exactly (7 in → 18 cm, 8.5 in → 22 cm, …).
    var centimeterLabel: String {
        "\(Self.centimeters(width))×\(Self.centimeters(height)) cm"
    }

    /// e.g. `"7×7 in (18×18 cm)"`.
    var dualLabel: String { "\(inchLabel) (\(centimeterLabel))" }

    private static func formatInches(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func centimeters(_ inches: Double) -> Int {
        Int((inches * centimetersPerInch).rounded())
    }
}
