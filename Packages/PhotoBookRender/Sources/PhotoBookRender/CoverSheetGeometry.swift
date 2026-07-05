import CoreGraphics
import PhotoBookCore

/// Pure layout math for the three-panel cover sheet (back | spine | front),
/// used by `CoverSheetView`. All panels share the trim height; the two trim
/// panels are `trimSize.aspectRatio` wide, the spine is proportional to
/// `spineInches / trimSize.height`. The sheet is scaled to fit `available`
/// (aspect-preserving) and returned with its back panel at the origin.
public enum CoverSheetGeometry {

    public struct Layout: Equatable, Sendable {
        public var back: CGRect
        public var spine: CGRect
        public var front: CGRect
        public var size: CGSize   // union of the three panels (for centering)
    }

    public static func layout(available: CGSize, trimSize: SizeInches,
                              spineInches: Double) -> Layout {
        let trimAspect = CGFloat(trimSize.aspectRatio)                        // w / h
        let spinePerHeight = CGFloat(trimSize.height > 0 ? spineInches / trimSize.height : 0)
        let sheetAspect = 2 * trimAspect + spinePerHeight                     // sheetW / H
        guard sheetAspect > 0, available.width > 0, available.height > 0 else {
            return Layout(back: .zero, spine: .zero, front: .zero, size: .zero)
        }
        let height = min(available.height, available.width / sheetAspect)
        let trimW = height * trimAspect
        let spineW = height * spinePerHeight
        let back = CGRect(x: 0, y: 0, width: trimW, height: height)
        let spine = CGRect(x: trimW, y: 0, width: spineW, height: height)
        let front = CGRect(x: trimW + spineW, y: 0, width: trimW, height: height)
        return Layout(back: back, spine: spine, front: front,
                      size: CGSize(width: 2 * trimW + spineW, height: height))
    }
}
