import Foundation
import Testing
import PhotoBookCore

@Suite struct BookSerializerTests {

    /// A fully-populated book exercising every model type, with fixed UUIDs
    /// and dates so encodes are reproducible.
    private func sampleBook() -> Book {
        var book = Book(title: "Summer 2025", presetID: "blurb-small-square", style: .standard)
        book.photoLibrary = [
            PhotoRef(id: PhotoID(rawValue: "p1"),
                     source: .photoKit(localIdentifier: "LOCAL-1"),
                     pixelWidth: 4032, pixelHeight: 3024,
                     captureDate: Date(timeIntervalSinceReferenceDate: 700_000_000)),
            PhotoRef(id: PhotoID(rawValue: "p2"),
                     source: .file(bookmark: Data([0xAA, 0xBB])),
                     pixelWidth: 3024, pixelHeight: 4032,
                     captureDate: nil, isMissing: true)
        ]
        book.pages = [
            Page(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                 role: .cover,
                 origin: .generated(GeneratedLayoutParams(seed: 42, boxes: [.full])),
                 photoSlots: [PhotoSlot(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                                        frame: NormRect(x: 0.1, y: 0.1, width: 0.8, height: 0.6),
                                        photoID: PhotoID(rawValue: "p1"),
                                        crop: .full, isLocked: true)],
                 textSlots: [TextSlot(id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
                                      frame: NormRect(x: 0.1, y: 0.75, width: 0.8, height: 0.15),
                                      text: StyledText(string: "Summer 2025", fontName: "",
                                                       pointSizeFactor: 0.05,
                                                       colorHex: "#222222", alignment: .center))],
                 isLocked: false),
            Page(id: UUID(uuidString: "22222222-3333-4444-5555-666666666666")!,
                 role: .standard,
                 origin: .template(id: "single-hero"),
                 photoSlots: [PhotoSlot(id: UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")!,
                                        frame: .full,
                                        photoID: PhotoID(rawValue: "p2"))],
                 textSlots: [],
                 isLocked: false)
        ]
        return book
    }

    private func expectCorruptData(_ data: Data) {
        do {
            _ = try BookSerializer.decode(data)
            Issue.record("Expected BookSerializer.decode to throw .corruptData")
        } catch let error as BookSerializerError {
            guard case .corruptData = error else {
                Issue.record("Expected .corruptData, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected BookSerializerError, got \(error)")
        }
    }

    @Test func initSetsDefaults() {
        let book = Book(title: "T", presetID: "blurb-mini-square", style: .standard)
        #expect(book.schemaVersion == Book.currentSchemaVersion)
        #expect(book.title == "T")
        #expect(book.presetID == "blurb-mini-square")
        #expect(book.style == .standard)
        #expect(book.photoLibrary.isEmpty)
        #expect(book.pages.isEmpty)
    }

    @Test func codableRoundTrip() throws {
        let original = sampleBook()
        let decoded = try BookSerializer.decode(try BookSerializer.encode(original))
        #expect(decoded == original)
    }

    @Test func encodeIsByteStable() throws {
        let book = sampleBook()
        let first = try BookSerializer.encode(book)
        let second = try BookSerializer.encode(book)
        #expect(first == second)
        // decode → re-encode is also byte-identical
        let reencoded = try BookSerializer.encode(BookSerializer.decode(first))
        #expect(reencoded == first)
    }

    @Test func encodeIsPrettyWithSortedKeys() throws {
        let json = String(decoding: try BookSerializer.encode(sampleBook()), as: UTF8.self)
        #expect(json.contains("\n"))   // pretty-printed
        // sorted keys: "pages" < "photoLibrary" < "schemaVersion" at top level
        let pages = try #require(json.range(of: "\"pages\""))
        let photoLibrary = try #require(json.range(of: "\"photoLibrary\""))
        let schemaVersion = try #require(json.range(of: "\"schemaVersion\""))
        #expect(pages.lowerBound < photoLibrary.lowerBound)
        #expect(photoLibrary.lowerBound < schemaVersion.lowerBound)
    }

    @Test func decodeRejectsNewerSchemaVersion() throws {
        var book = sampleBook()
        book.schemaVersion = 99
        let data = try BookSerializer.encode(book)
        #expect(throws: BookSerializerError.unsupportedSchemaVersion(99)) {
            _ = try BookSerializer.decode(data)
        }
    }

    @Test func decodeRejectsNonPositiveSchemaVersion() throws {
        var book = sampleBook()
        book.schemaVersion = 0
        let data = try BookSerializer.encode(book)
        #expect(throws: BookSerializerError.unsupportedSchemaVersion(0)) {
            _ = try BookSerializer.decode(data)
        }
    }

    @Test func decodeRejectsGarbageAsCorruptData() {
        expectCorruptData(Data("not json at all {{{".utf8))
    }

    @Test func decodeRejectsValidJSONMissingFieldsAsCorruptData() {
        expectCorruptData(Data(#"{"schemaVersion": 1, "title": "incomplete"}"#.utf8))
    }

    // MARK: - C2: spread registry + schema migration

    @Test func initDefaultsSpreadsToEmpty() {
        let book = Book(title: "T", presetID: "blurb-mini-square", style: .standard)
        #expect(book.spreads.isEmpty)
    }

    /// A `book.json` at the OLD schema version (no `spreads`, no per-page
    /// spreadID/half) decodes into a book with empty spreads and nil page
    /// bindings, re-stamped at the new current version.
    @Test func oldSchemaWithoutSpreadsDecodesWithEmptyRegistryAndNilBindings() throws {
        // schemaVersion 1 is the pre-spread version. Pages carry no spread
        // binding keys (back-compat: absent → nil).
        let json = """
        {
          "schemaVersion": 1,
          "title": "Legacy",
          "presetID": "blurb-small-square",
          "style": {"pageMargin": 0.05, "gutter": 0.02, "cornerRadius": 0,
                    "backgroundColorHex": "#FFFFFF", "defaultFontName": "HelveticaNeue"},
          "photoLibrary": [],
          "pages": [
            {"id": "11111111-2222-3333-4444-555555555555", "role": "cover",
             "origin": {"template": {"id": "cover-hero"}},
             "photoSlots": [], "textSlots": [], "isLocked": false}
          ]
        }
        """.data(using: .utf8)!
        let decoded = try BookSerializer.decode(json)
        #expect(decoded.spreads.isEmpty)
        #expect(decoded.pages.allSatisfy { $0.spreadID == nil && $0.half == nil })
        // Re-stamped at the current version and round-trips stably.
        #expect(decoded.schemaVersion == Book.currentSchemaVersion)
        let reencoded = try BookSerializer.encode(decoded)
        #expect(try BookSerializer.encode(BookSerializer.decode(reencoded)) == reencoded)
    }

    /// A book carrying spreads + bound pages round-trips byte-stably.
    @Test func bookWithSpreadsRoundTripsStably() throws {
        var book = sampleBook()
        let sid = UUID(uuidString: "DDDDDDDD-EEEE-FFFF-0000-111111111111")!
        book.spreads = [Spread(id: sid, origin: .template(id: "spread-panorama"),
                               photoSlots: [SpreadPhotoSlot(frame: .full,
                                                            photoID: PhotoID(rawValue: "p1"))])]
        book.pages[1].spreadID = sid
        book.pages[1].half = .left
        let first = try BookSerializer.encode(book)
        let decoded = try BookSerializer.decode(first)
        #expect(decoded == book)
        #expect(try BookSerializer.encode(decoded) == first)
    }

    // MARK: - C3: photo importance + schema v3

    @Test func newBooksUseCurrentSchemaVersion() {
        let book = Book(title: "T", presetID: "p", style: .standard)
        #expect(book.schemaVersion == 4)
        #expect(Book.currentSchemaVersion == 4)
    }

    @Test func v2DocumentMigratesToV3WithNilImportance() throws {
        // Encode a current book, then back-date its schemaVersion to 2 and
        // remove any importance key to simulate a real v2 document on disk
        // (v2 predates the field, so the absent-key → nil path is what loads).
        var book = Book(title: "Old", presetID: "p", style: .standard)
        book.photoLibrary = [PhotoRef(id: PhotoID(rawValue: "a"),
                                      source: .file(bookmark: Data()),
                                      pixelWidth: 4000, pixelHeight: 3000)]
        let data = try BookSerializer.encode(book)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["schemaVersion"] = 2
        if var library = object["photoLibrary"] as? [[String: Any]] {
            for i in library.indices { library[i].removeValue(forKey: "importance") }
            object["photoLibrary"] = library
        }
        let v2 = try JSONSerialization.data(withJSONObject: object)

        let migrated = try BookSerializer.decode(v2)
        #expect(migrated.schemaVersion == 4)
        #expect(migrated.photoLibrary.first?.importance == nil)
    }
}
