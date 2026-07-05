import SwiftUI

/// Anchor bounds of the currently highlighted photo slot, so an editor overlay
/// (e.g. the photo-actions popover) can position itself over that slot.
public struct SelectedSlotBoundsKey: PreferenceKey {
    public static let defaultValue: Anchor<CGRect>? = nil
    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
