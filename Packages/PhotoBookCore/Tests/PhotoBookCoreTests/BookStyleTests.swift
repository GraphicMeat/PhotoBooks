import Foundation
import Testing
import PhotoBookCore

@Suite struct BookStyleTests {

    @Test func standardStyleValues() {
        let style = BookStyle.standard
        #expect(style.pageMargin == 0.05)
        #expect(style.gutter == 0.02)
        #expect(style.cornerRadius == 0)
        #expect(style.backgroundColorHex == "#FFFFFF")
        #expect(style.defaultFontName == "HelveticaNeue")
    }

    @Test func codableRoundTrip() throws {
        let original = BookStyle(pageMargin: 0.08, gutter: 0.03, cornerRadius: 0.01,
                                 backgroundColorHex: "#FAFAF0", defaultFontName: "Georgia")
        let decoded = try JSONDecoder().decode(BookStyle.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    // D1: edgeStyle field
    @Test func standardEdgeStyleIsFramed() {
        #expect(BookStyle.standard.edgeStyle == .framed)
    }

    @Test func edgeStyleRoundTrips() throws {
        for style in EdgeStyle.allCases {
            var bookStyle = BookStyle.standard
            bookStyle.edgeStyle = style
            let data = try JSONEncoder().encode(bookStyle)
            let decoded = try JSONDecoder().decode(BookStyle.self, from: data)
            #expect(decoded.edgeStyle == style)
        }
    }

    @Test func jsonWithoutEdgeStyleKeyDecodesFramed() throws {
        // Old-format JSON with neither "edgeStyle" nor "borderless" → framed.
        let json = """
        {"pageMargin":0.05,"gutter":0.02,"cornerRadius":0,
         "backgroundColorHex":"#FFFFFF","defaultFontName":"HelveticaNeue"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BookStyle.self, from: json)
        #expect(decoded.edgeStyle == .framed)
    }

    @Test func legacyBorderlessTrueMigratesToBorderless() throws {
        // Old-format JSON with legacy "borderless": true → .borderless.
        let json = """
        {"pageMargin":0.05,"gutter":0.02,"cornerRadius":0,
         "backgroundColorHex":"#FFFFFF","defaultFontName":"HelveticaNeue","borderless":true}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BookStyle.self, from: json)
        #expect(decoded.edgeStyle == .borderless)
    }

    @Test func legacyBorderlessFalseMigratesToFramed() throws {
        let json = """
        {"pageMargin":0.05,"gutter":0.02,"cornerRadius":0,
         "backgroundColorHex":"#FFFFFF","defaultFontName":"HelveticaNeue","borderless":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BookStyle.self, from: json)
        #expect(decoded.edgeStyle == .framed)
    }
}
