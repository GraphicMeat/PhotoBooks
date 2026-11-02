import Foundation

/// Whether this install has donated, which removes the sponsor pages from
/// every export.
public enum SupporterStatus {
    public static let defaultsKey = "photobooks.hasDonated"

    public static func isSupporter(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    /// `photobooks://donated`: where the Developer ID build lands after Stripe
    /// confirms a donation. Returns whether the link was this one.
    @discardableResult
    public static func handle(_ url: URL, defaults: UserDefaults = .standard) -> Bool {
        guard url.scheme == "photobooks", url.host() == "donated" else { return false }
        defaults.set(true, forKey: defaultsKey)
        return true
    }
}
