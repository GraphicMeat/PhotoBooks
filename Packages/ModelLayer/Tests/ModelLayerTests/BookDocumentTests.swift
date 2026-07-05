import Foundation
import PhotoBookCore
import Testing
@testable import ModelLayer

@Suite struct BookDocumentTests {

    private func sampleBook(title: String = "Doc Test") -> Book {
        var book = Book(title: title, presetID: "blurb-small-square", style: .standard)
        book.photoLibrary = [
            PhotoRef(id: PhotoID(rawValue: "p1"), source: .file(bookmark: Data([0x01])),
                     pixelWidth: 4032, pixelHeight: 3024)
        ]
        book.pages = [
            Page(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                 role: .cover, origin: .template(id: "cover-hero"),
                 photoSlots: [PhotoSlot(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                                        frame: .full, photoID: PhotoID(rawValue: "p1"))])
        ]
        return book
    }

    // MARK: Package round trip

    @Test func firstSavePackageHasBookJSONAndEmptyThumbnails() throws {
        let book = sampleBook()
        let package = try BookDocument.makePackage(book: book, existing: nil)
        #expect(package.isDirectory)
        let children = package.fileWrappers ?? [:]
        #expect(Set(children.keys) == ["book.json", "thumbnails"])
        #expect(children["thumbnails"]?.isDirectory == true)
        let decoded = try BookDocument.book(fromPackage: package)
        #expect(decoded == book)
    }

    @Test func resavePreservesThumbnailsAndWritesBackup() throws {
        let first = sampleBook(title: "First")
        let firstPackage = try BookDocument.makePackage(book: first, existing: nil)
        let firstEncoded = try BookSerializer.encode(first)

        // Simulate the app's thumbnail cache having written a file.
        let thumbData = Data([0xCA, 0xFE])
        let thumb = FileWrapper(regularFileWithContents: thumbData)
        thumb.preferredFilename = "p1-256.png"
        firstPackage.fileWrappers?["thumbnails"]?.addFileWrapper(thumb)

        var second = first
        second.title = "Second"
        let secondPackage = try BookDocument.makePackage(book: second, existing: firstPackage)

        let children = secondPackage.fileWrappers ?? [:]
        #expect(Set(children.keys) == ["book.json", "book.json.backup", "thumbnails"])

        // Backup is byte-identical to the previous save's book.json.
        #expect(children["book.json.backup"]?.regularFileContents == firstEncoded)
        // Current book.json is the new content.
        #expect(try BookDocument.book(fromPackage: secondPackage) == second)
        // Thumbnails passed through untouched.
        let thumbs = children["thumbnails"]?.fileWrappers ?? [:]
        #expect(thumbs["p1-256.png"]?.regularFileContents == thumbData)
    }

    @Test func corruptBookJSONRecoversFromBackup() throws {
        let good = sampleBook(title: "Good")
        let bookWrapper = FileWrapper(regularFileWithContents: Data("not json {{{".utf8))
        bookWrapper.preferredFilename = "book.json"
        let backupWrapper = FileWrapper(regularFileWithContents: try BookSerializer.encode(good))
        backupWrapper.preferredFilename = "book.json.backup"
        let package = FileWrapper(directoryWithFileWrappers: [
            "book.json": bookWrapper,
            "book.json.backup": backupWrapper
        ])
        let recovered = try BookDocument.book(fromPackage: package)
        #expect(recovered == good)
    }

    @Test func corruptBookJSONWithoutBackupThrowsReadableError() {
        let bookWrapper = FileWrapper(regularFileWithContents: Data("not json {{{".utf8))
        let package = FileWrapper(directoryWithFileWrappers: ["book.json": bookWrapper])
        #expect(throws: BookDocumentError.self) {
            _ = try BookDocument.book(fromPackage: package)
        }
    }

    @Test func unsupportedSchemaVersionThrowsWithReadableDescription() throws {
        var future = sampleBook()
        future.schemaVersion = 99
        let bookWrapper = FileWrapper(regularFileWithContents: try BookSerializer.encode(future))
        let package = FileWrapper(directoryWithFileWrappers: ["book.json": bookWrapper])
        do {
            _ = try BookDocument.book(fromPackage: package)
            Issue.record("Expected unsupportedSchemaVersion to throw")
        } catch let error as BookDocumentError {
            guard case .unsupportedSchemaVersion(99) = error else {
                Issue.record("Expected .unsupportedSchemaVersion(99), got \(error)")
                return
            }
            let description = error.localizedDescription
            #expect(description.contains("99"))
            #expect(description.contains("newer version"))
        } catch {
            Issue.record("Expected BookDocumentError, got \(error)")
        }
    }

    @Test func packageWithoutBookJSONThrows() {
        let package = FileWrapper(directoryWithFileWrappers: [:])
        #expect(throws: BookDocumentError.self) {
            _ = try BookDocument.book(fromPackage: package)
        }
    }

    @Test func corruptBookJSONWithUnsupportedSchemaBackupThrowsSchemaError() throws {
        // Corrupt primary book.json; backup contains a future schema version (99).
        // The recovery path must surface .unsupportedSchemaVersion, not the
        // generic .corruptWithoutUsableBackup error.
        let corruptWrapper = FileWrapper(regularFileWithContents: Data("not json {{{".utf8))
        corruptWrapper.preferredFilename = "book.json"

        // Build a raw JSON payload that looks valid enough for schemaVersion
        // probing but has schemaVersion = 99 so BookSerializer rejects it.
        let futureJSONString = "{\"schemaVersion\":99,\"title\":\"Future\",\"presetID\":\"x\",\"style\":{\"backgroundColorHex\":\"#ffffff\",\"defaultFontName\":\"Helvetica\"},\"photoLibrary\":[],\"pages\":[]}"
        let futureJSON = Data(futureJSONString.utf8)
        let backupWrapper = FileWrapper(regularFileWithContents: futureJSON)
        backupWrapper.preferredFilename = "book.json.backup"

        let package = FileWrapper(directoryWithFileWrappers: [
            "book.json": corruptWrapper,
            "book.json.backup": backupWrapper
        ])

        do {
            _ = try BookDocument.book(fromPackage: package)
            Issue.record("Expected unsupportedSchemaVersion to throw")
        } catch let error as BookDocumentError {
            guard case .unsupportedSchemaVersion(99) = error else {
                Issue.record("Expected .unsupportedSchemaVersion(99), got \(error)")
                return
            }
            #expect(error.localizedDescription.contains("99"))
        } catch {
            Issue.record("Expected BookDocumentError, got \(error)")
        }
    }

    // MARK: mutate + undo

    @MainActor
    @Test func mutateAppliesChangeAndRegistersInverseUndo() {
        let document = BookDocument(book: sampleBook(title: "Original"))
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false

        undoManager.beginUndoGrouping()
        document.mutate({ $0.title = "Edited" }, undoManager: undoManager)
        undoManager.endUndoGrouping()

        #expect(document.book.title == "Edited")
        #expect(undoManager.canUndo)

        undoManager.undo()
        #expect(document.book.title == "Original")
        #expect(undoManager.canRedo)

        undoManager.redo()
        #expect(document.book.title == "Edited")
    }

    @MainActor
    @Test func refsByIDTracksBookMutations() {
        let document = BookDocument(book: sampleBook())
        #expect(document.refsByID[PhotoID(rawValue: "p1")]?.pixelWidth == 4032)
        document.mutate({ book in
            book.photoLibrary.append(PhotoRef(id: PhotoID(rawValue: "p2"),
                                              source: .file(bookmark: Data()),
                                              pixelWidth: 100, pixelHeight: 100))
        }, undoManager: nil)
        #expect(document.refsByID.count == 2)
        #expect(document.refsByID[PhotoID(rawValue: "p2")] != nil)
    }

    @MainActor
    @Test func noOpMutationRegistersNoUndo() {
        let document = BookDocument(book: sampleBook())
        let undoManager = UndoManager()
        // No grouping here on purpose: an explicitly opened-and-closed EMPTY
        // group itself counts as an undoable item, which would mask the bug
        // this test guards against (no-op edits polluting the undo stack).
        document.mutate({ _ in }, undoManager: undoManager)
        #expect(!undoManager.canUndo)
    }
}
