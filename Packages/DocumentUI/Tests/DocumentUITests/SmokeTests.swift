import PhotoBookCore
import PhotoBookImport
import PhotoBookRender
import Testing

@Suite struct SmokeTests {

    /// Proves all three packages link into the app test bundle and the
    /// bundled preset library is reachable.
    @Test func packagesLinkIntoAppTestBundle() {
        let presets = PresetLibrary.all()
        #expect(presets.count == 11)
        let book = Book(title: "Smoke", presetID: presets[0].id, style: .standard)
        #expect(book.pages.isEmpty)
        _ = FileSystemProvider()
        _ = PhotoKitProvider()
    }
}
