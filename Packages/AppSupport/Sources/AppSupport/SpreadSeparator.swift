/// A spread separator line is drawn only for a true facing pair — both a left
/// and a right page present (not the cover row or an odd tail). Editor-only.
public func spreadSeparatorVisible(left: Int?, right: Int?) -> Bool {
    left != nil && right != nil
}
