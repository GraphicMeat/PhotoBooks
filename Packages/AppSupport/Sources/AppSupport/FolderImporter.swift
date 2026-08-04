import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

public extension View {
    /// Open panel that can pick the folder you are currently browsing, and
    /// that can explain itself.
    ///
    /// SwiftUI's `fileImporter` disables Open once you step *inside* a folder,
    /// so the folder you are looking at cannot be chosen — users work around
    /// it by cancelling and re-opening the panel with the folder selected in
    /// its parent. It also can't set a prompt or a message, so a panel full of
    /// greyed-out files never says why. macOS therefore drives `NSOpenPanel`
    /// directly; iOS keeps `fileImporter`, which behaves on that platform.
    func nativeImporter(isPresented: Binding<Bool>,
                        contentTypes: [UTType] = [.folder],
                        prompt: String? = nil,
                        message: String? = nil,
                        onPick: @escaping (URL) -> Void) -> some View {
        modifier(NativeImporterModifier(isPresented: isPresented,
                                        contentTypes: contentTypes,
                                        prompt: prompt,
                                        message: message,
                                        onPick: onPick))
    }
}

private struct NativeImporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    let contentTypes: [UTType]
    let prompt: String?
    let message: String?
    let onPick: (URL) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.onChange(of: isPresented) { _, presented in
            guard presented else { return }
            isPresented = false   // the panel is its own window, not a sheet
            let fileTypes = contentTypes.filter { $0 != .folder }
            let panel = NSOpenPanel()
            panel.canChooseFiles = !fileTypes.isEmpty
            panel.canChooseDirectories = contentTypes.contains(.folder)
            panel.allowedContentTypes = fileTypes
            panel.allowsMultipleSelection = false
            if let prompt { panel.prompt = prompt }
            if let message { panel.message = message }
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                onPick(url)
            }
        }
        #else
        content.fileImporter(isPresented: $isPresented,
                             allowedContentTypes: contentTypes) { result in
            if case .success(let url) = result { onPick(url) }
        }
        #endif
    }
}
