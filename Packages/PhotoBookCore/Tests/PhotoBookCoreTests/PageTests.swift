import Foundation
import Testing
import PhotoBookCore

@Suite struct PageTests {

    @Test func generatedLayoutParamsCodableRoundTrip() throws {
        let original = GeneratedLayoutParams(seed: 0xDEADBEEF, boxes: [
            NormRect(x: 0, y: 0, width: 0.5, height: 1),
            NormRect(x: 0.5, y: 0, width: 0.5, height: 1)
        ])
        let decoded = try JSONDecoder().decode(GeneratedLayoutParams.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func layoutOriginTemplateCodableRoundTrip() throws {
        let original = LayoutOrigin.template(id: "grid-2x2-square")
        let decoded = try JSONDecoder().decode(LayoutOrigin.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func layoutOriginGeneratedCodableRoundTrip() throws {
        let original = LayoutOrigin.generated(GeneratedLayoutParams(seed: 7, boxes: [.full]))
        let decoded = try JSONDecoder().decode(LayoutOrigin.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func pageRoleRawValues() {
        #expect(PageRole.standard.rawValue == "standard")
        #expect(PageRole.cover.rawValue == "cover")
    }

    @Test func pageCodableRoundTrip() throws {
        let original = Page(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            role: .cover,
            origin: .generated(GeneratedLayoutParams(seed: 42, boxes: [.full])),
            photoSlots: [PhotoSlot(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                                   frame: .full, photoID: PhotoID(rawValue: "p1"),
                                   crop: .full, isLocked: true)],
            textSlots: [TextSlot(id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
                                 frame: NormRect(x: 0.1, y: 0.8, width: 0.8, height: 0.1),
                                 text: StyledText(string: "Title", pointSizeFactor: 0.05),
                                 isLocked: false)],
            isLocked: true
        )
        let decoded = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func pageDefaults() {
        let page = Page(origin: .template(id: "single-hero"))
        #expect(page.role == .standard)
        #expect(page.photoSlots.isEmpty)
        #expect(page.textSlots.isEmpty)
        #expect(page.isLocked == false)
    }

    // D1: edgeStyleOverride field
    @Test func edgeStyleOverrideDefaultsToNil() {
        let page = Page(origin: .template(id: "single-hero"))
        #expect(page.edgeStyleOverride == nil)
    }

    @Test func edgeStyleOverrideRoundTrips() throws {
        for style in EdgeStyle.allCases {
            let page = Page(origin: .template(id: "single-hero"), edgeStyleOverride: style)
            let data = try JSONEncoder().encode(page)
            let decoded = try JSONDecoder().decode(Page.self, from: data)
            #expect(decoded.edgeStyleOverride == style)
        }
    }

    @Test func jsonWithoutEdgeStyleOverrideDecodesNil() throws {
        // A page that never set an override round-trips with edgeStyleOverride nil.
        let page = Page(origin: .template(id: "single-hero"))
        let decoded = try JSONDecoder().decode(Page.self, from: try JSONEncoder().encode(page))
        #expect(decoded.edgeStyleOverride == nil)
    }

    @Test func legacyBorderlessOverrideMigrates() throws {
        // Legacy JSON: borderlessOverride true → .borderless, false → .framed,
        // absent → nil.
        func decode(_ overrideJSON: String) throws -> Page {
            let json = """
            {"id":"00000000-0000-0000-0000-000000000000","role":"standard",
             "origin":{"template":{"id":"single-hero"}},
             "photoSlots":[],"textSlots":[],"isLocked":false\(overrideJSON)}
            """.data(using: .utf8)!
            return try JSONDecoder().decode(Page.self, from: json)
        }
        #expect(try decode(",\"borderlessOverride\":true").edgeStyleOverride == .borderless)
        #expect(try decode(",\"borderlessOverride\":false").edgeStyleOverride == .framed)
        #expect(try decode("").edgeStyleOverride == nil)
    }

    // C2: spread binding fields
    @Test func pageWithoutSpreadBindingHasNilSpreadIDAndHalf() {
        let page = Page(origin: .template(id: "single-hero"))
        #expect(page.spreadID == nil)
        #expect(page.half == nil)
    }

    @Test func pageSpreadBindingRoundTrips() throws {
        let sid = UUID(uuidString: "DDDDDDDD-EEEE-FFFF-0000-111111111111")!
        let page = Page(origin: .template(id: "spread-panorama"),
                        spreadID: sid, half: .left)
        let decoded = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        #expect(decoded.spreadID == sid)
        #expect(decoded.half == .left)
    }

    @Test func jsonWithoutSpreadBindingDecodesNil() throws {
        let json = """
        {"id":"11111111-2222-3333-4444-555555555555","role":"standard",
         "origin":{"template":{"id":"hero"}},"photoSlots":[],"textSlots":[],"isLocked":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Page.self, from: json)
        #expect(decoded.spreadID == nil)
        #expect(decoded.half == nil)
    }
}
