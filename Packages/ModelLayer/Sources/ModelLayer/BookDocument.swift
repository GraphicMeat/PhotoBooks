import Foundation
import PhotoBookCore
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

extension UTType {
    /// The `.photobookGraphicMeat` document package, declared in the app's
    /// Info.plist (UTExportedTypeDeclarations) as conforming to
    /// com.apple.package.
    public static let photoBook = UTType(exportedAs: "com.graphicMeat.PhotoBooks.book")
}

/// Errors surfaced to the user when a `.photobook` package cannot be opened.
enum BookDocumentError: LocalizedError {
    case packageMissingBookJSON
    case corruptWithoutUsableBackup
    case unsupportedSchemaVersion(Int)

    var errorDescription: String? {
        switch self {
        case .packageMissingBookJSON:
            return "This file is not a complete PhotoBooks book (book.json is missing)."
        case .corruptWithoutUsableBackup:
            return "This book's data is damaged and its built-in backup could not be read either."
        case .unsupportedSchemaVersion(let version):
            return "This book was saved by a newer version of PhotoBooks (format \(version); this version reads up to \(Book.currentSchemaVersion)). Update PhotoBooks to open it."
        }
    }
}

/// The `.photobook` document: a package wrapping `book.json` (canonical,
/// `BookSerializer`-encoded), a `thumbnails/` cache directory (preserved
/// across saves, never interpreted here), and one `book.json.backup`
/// generation (the previously saved `book.json`, used for corruption
/// recovery).
///
/// Concurrency: `ReferenceFileDocument` requires `Sendable`. The invariant
/// making `@unchecked` sound: `book` is only read/written on the main actor
/// (SwiftUI document UI + `mutate`); the background save path receives an
/// immutable `Book` VALUE via `snapshot(contentType:)` and never touches
/// the reference again.
public final class BookDocument: ReferenceFileDocument, @unchecked Sendable {
    public typealias Snapshot = Book

    public static var readableContentTypes: [UTType] { [.photoBook] }

    @Published public internal(set) var book: Book {
        didSet { refSnapshot.withLock { $0 = Self.refsByID(of: book) } }
    }

    /// Thread-safe snapshot of `book.photoLibrary` keyed by ID. This is what
    /// `AppImageStore`'s `refProvider` closure reads: image loads resolve on
    /// whatever executor the store runs on, so they must not touch the
    /// main-actor `book` property directly.
    private let refSnapshot = Mutex<[PhotoID: PhotoRef]>([:])

    public var refsByID: [PhotoID: PhotoRef] {
        refSnapshot.withLock { $0 }
    }

    private static func refsByID(of book: Book) -> [PhotoID: PhotoRef] {
        Dictionary(book.photoLibrary.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public init(book: Book) {
        self.book = book
        refSnapshot.withLock { $0 = Self.refsByID(of: book) }
    }

    public convenience init() {
        self.init(book: Book(title: "Untitled", presetID: PresetLibrary.all()[0].id, style: .standard))
    }

    public convenience init(configuration: ReadConfiguration) throws {
        self.init(book: try Self.book(fromPackage: configuration.file))
    }

    public func snapshot(contentType: UTType) throws -> Book {
        book
    }

    public func fileWrapper(snapshot: Book, configuration: WriteConfiguration) throws -> FileWrapper {
        try Self.makePackage(book: snapshot, existing: configuration.existingFile)
    }

    // MARK: - Mutation + undo

    /// THE single mutation funnel: every model edit (Plan 5 builds all
    /// editing on this) goes through here so that undo is uniform —
    /// the inverse is a whole-`Book` snapshot, and redo falls out of
    /// `registerUndo` re-registering during undo.
    @MainActor
    public func mutate(_ transform: (inout Book) -> Void, undoManager: UndoManager?) {
        let previous = book
        var updated = book
        transform(&updated)
        guard updated != previous else { return }
        book = updated
        undoManager?.registerUndo(withTarget: self) { document in
            document.mutate({ $0 = previous }, undoManager: undoManager)
        }
    }

    // MARK: - Package layout (static, unit-testable without a document)

    /// Decodes a book from a `.photobook` package wrapper. `book.json` is
    /// canonical; on `corruptData` the `book.json.backup` generation is
    /// tried before giving up. An unsupported (newer) schema version is NOT
    /// recovered from backup — it is reported, with a readable description,
    /// so the user knows to update the app.
    static func book(fromPackage package: FileWrapper) throws -> Book {
        guard let data = package.fileWrappers?["book.json"]?.regularFileContents else {
            throw BookDocumentError.packageMissingBookJSON
        }
        do {
            return try BookSerializer.decode(data)
        } catch BookSerializerError.corruptData {
            guard let backupData = package.fileWrappers?["book.json.backup"]?.regularFileContents
            else { throw BookDocumentError.corruptWithoutUsableBackup }
            do {
                return try BookSerializer.decode(backupData)
            } catch BookSerializerError.unsupportedSchemaVersion(let v) {
                throw BookDocumentError.unsupportedSchemaVersion(v)
            } catch {
                throw BookDocumentError.corruptWithoutUsableBackup
            }
        } catch BookSerializerError.unsupportedSchemaVersion(let version) {
            throw BookDocumentError.unsupportedSchemaVersion(version)
        }
    }

    /// Builds the package wrapper for a save: fresh `book.json`, the
    /// previous save's `book.json` carried over as `book.json.backup`
    /// (one generation), and the existing `thumbnails/` directory passed
    /// through untouched (created empty on first save).
    static func makePackage(book: Book, existing: FileWrapper?) throws -> FileWrapper {
        let package = FileWrapper(directoryWithFileWrappers: [:])

        let bookWrapper = FileWrapper(regularFileWithContents: try BookSerializer.encode(book))
        bookWrapper.preferredFilename = "book.json"
        package.addFileWrapper(bookWrapper)

        if let previous = existing?.fileWrappers?["book.json"]?.regularFileContents {
            let backupWrapper = FileWrapper(regularFileWithContents: previous)
            backupWrapper.preferredFilename = "book.json.backup"
            package.addFileWrapper(backupWrapper)
        }

        if let thumbnails = existing?.fileWrappers?["thumbnails"] {
            package.addFileWrapper(thumbnails)
        } else {
            let thumbnails = FileWrapper(directoryWithFileWrappers: [:])
            thumbnails.preferredFilename = "thumbnails"
            package.addFileWrapper(thumbnails)
        }

        return package
    }
}
