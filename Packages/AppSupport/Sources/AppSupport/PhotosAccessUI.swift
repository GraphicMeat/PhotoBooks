import Photos

/// Which UI the setup flow shows for a Photos authorization status (spec
/// error handling: "Photos permission denied/limited → explainer + Settings
/// deep-link; limited mode functional"). Pure decision function — the one
/// unit-testable piece of the permission flow; `NewBookSetupView` wires it.
public enum PhotosAccessUI: Equatable {
    /// Full access: load collections normally.
    case proceed
    /// `.limited` (iOS 14+): load collections normally AND show the info
    /// banner with the limited-library "Manage…" button. Never returned in
    /// practice on macOS — macOS has no limited mode.
    case proceedWithLimitedBanner
    /// Denied/restricted (or somehow still undetermined after a request):
    /// show the explainer with the Settings deep-link and the folder
    /// escape hatch.
    case explainer
}

public func photosAccessUI(for status: PHAuthorizationStatus) -> PhotosAccessUI {
    switch status {
    case .authorized:
        return .proceed
    case .limited:
        return .proceedWithLimitedBanner
    case .notDetermined, .restricted, .denied:
        return .explainer
    @unknown default:
        return .explainer
    }
}
