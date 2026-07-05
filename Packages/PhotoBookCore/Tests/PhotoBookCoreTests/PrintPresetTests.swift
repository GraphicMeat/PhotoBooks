import Foundation
import Testing
import PhotoBookCore

@Suite struct PrintPresetTests {

    @Test func libraryLoadsAllElevenPresets() {
        let all = PresetLibrary.all()
        #expect(all.count == 11)
        #expect(all.map(\.id) == [
            "blurb-mini-square",
            "blurb-small-square",
            "blurb-standard-landscape",
            "blurb-standard-portrait",
            "blurb-large-square",
            "blurb-large-landscape",
            "generic-a4-portrait",
            "generic-a4-landscape",
            "trade-5x8",
            "trade-6x9",
            "magazine-premium"
        ])
    }

    @Test func presetLookupByID() throws {
        let preset = try #require(PresetLibrary.preset(id: "blurb-small-square"))
        #expect(preset.displayName == "Blurb Small Square 7×7")
        #expect(preset.trimSize == SizeInches(width: 7, height: 7))
        #expect(preset.bleed == 0.125)
        #expect(preset.safeMargin == 0.25)
        #expect(preset.minPages == 20)
        #expect(preset.maxPages == 240)
        #expect(preset.spineBase == 0.25)
        #expect(preset.spinePerPage == 0.002252)
        #expect(PresetLibrary.preset(id: "no-such-preset") == nil)
    }

    @Test func newPresetsLoadWithExpectedTrim() throws {
        let trade = try #require(PresetLibrary.preset(id: "trade-5x8"))
        #expect(trade.displayName == "Trade 5×8")
        #expect(trade.trimSize == SizeInches(width: 5, height: 8))
        let mag = try #require(PresetLibrary.preset(id: "magazine-premium"))
        #expect(mag.trimSize == SizeInches(width: 8.5, height: 11))
    }

    @Test func aspectClassDerivationForAllBundledPresets() throws {
        let expectations: [(id: String, expected: AspectClass)] = [
            ("blurb-mini-square", .square),
            ("blurb-small-square", .square),
            ("blurb-standard-landscape", .landscape),
            ("blurb-standard-portrait", .portrait),
            ("blurb-large-square", .square),
            ("blurb-large-landscape", .landscape),
            ("generic-a4-portrait", .portrait),
            ("generic-a4-landscape", .landscape),
            ("trade-5x8", .portrait),
            ("trade-6x9", .portrait),
            ("magazine-premium", .portrait)
        ]
        for (id, expected) in expectations {
            let preset = try #require(PresetLibrary.preset(id: id))
            #expect(preset.aspectClass == expected, "preset \(id)")
        }
    }

    @Test func aspectClassToleranceBand() {
        func preset(width: Double, height: Double) -> PrintPreset {
            PrintPreset(id: "t", displayName: "t",
                        trimSize: SizeInches(width: width, height: height),
                        bleed: 0.125, safeMargin: 0.25, minPages: 20, maxPages: 240,
                        spineBase: 0.25, spinePerPage: 0.002252)
        }
        // within 5% of 1:1 → square
        #expect(preset(width: 1.04, height: 1).aspectClass == .square)
        #expect(preset(width: 1, height: 1.04).aspectClass == .square)
        // outside the band → landscape/portrait by aspect
        #expect(preset(width: 1.06, height: 1).aspectClass == .landscape)
        #expect(preset(width: 1, height: 1.06).aspectClass == .portrait)
    }

    @Test func printPresetCodableRoundTrip() throws {
        let original = try #require(PresetLibrary.preset(id: "blurb-large-landscape"))
        let decoded = try JSONDecoder().decode(PrintPreset.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func derivedAspectClassIsNotEncoded() throws {
        let original = try #require(PresetLibrary.preset(id: "blurb-mini-square"))
        let json = String(decoding: try JSONEncoder().encode(original), as: UTF8.self)
        #expect(!json.contains("aspectClass"))
    }
}
