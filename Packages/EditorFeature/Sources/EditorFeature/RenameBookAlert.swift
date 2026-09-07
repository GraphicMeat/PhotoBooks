import SwiftUI

/// The book-title editor. The title is what prints on the spine — before this
/// the only way to change it was hand-editing `book.json` inside the package
/// (issue #5) — and it also names the window and the exported files.
extension View {
    func renameBookAlert(isPresented: Binding<Bool>, draft: Binding<String>,
                         onSave: @escaping () -> Void) -> some View {
        alert(String(localized: "Book Title", bundle: .module), isPresented: isPresented) {
            TextField(String(localized: "Title", bundle: .module), text: draft)
                .accessibilityIdentifier("book-title-field")
            Button(String(localized: "Save", bundle: .module), action: onSave)
                .accessibilityIdentifier("book-title-save")
            Button(String(localized: "Cancel", bundle: .module), role: .cancel) { }
        } message: {
            Text("Printed on the spine, and used for the window title and exported filenames.",
                 bundle: .module)
        }
    }
}
