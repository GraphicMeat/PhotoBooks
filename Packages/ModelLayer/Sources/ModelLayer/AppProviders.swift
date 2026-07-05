import PhotoBookImport

/// The two photo providers, created once per document window and shared by
/// the setup flow and the image store.
public struct AppProviders: Sendable {
    public let fileSystem = FileSystemProvider()
    public let photoKit = PhotoKitProvider()

    public init() {}
}
