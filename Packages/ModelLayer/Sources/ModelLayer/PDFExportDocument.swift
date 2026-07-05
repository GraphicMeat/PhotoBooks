import SwiftUI
import UniformTypeIdentifiers

/// In-memory PDF bytes for `.fileExporter` (D11): single-file targets
/// render to a temporary URL first; the save panel then places these bytes
/// wherever the user chose, on both platforms.
public struct PDFExportDocument: FileDocument {
    public static let readableContentTypes: [UTType] = [.pdf]

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
