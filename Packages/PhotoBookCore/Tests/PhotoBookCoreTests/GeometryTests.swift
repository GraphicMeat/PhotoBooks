import Foundation
import Testing
import PhotoBookCore

@Suite struct GeometryTests {

    @Test func fullCoversUnitSquare() {
        #expect(NormRect.full == NormRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func insetShrinksAllEdges() {
        let inset = NormRect.full.inset(by: 0.1)
        #expect(abs(inset.x - 0.1) < 1e-12)
        #expect(abs(inset.y - 0.1) < 1e-12)
        #expect(abs(inset.width - 0.8) < 1e-12)
        #expect(abs(inset.height - 0.8) < 1e-12)
    }

    @Test func insetClampsSizeAtZero() {
        let collapsed = NormRect(x: 0, y: 0, width: 0.2, height: 0.2).inset(by: 0.5)
        #expect(collapsed.width == 0)
        #expect(collapsed.height == 0)
    }

    @Test func normRectAspectRatioIsWidthOverHeight() {
        #expect(NormRect(x: 0, y: 0, width: 0.5, height: 0.25).aspectRatio == 2.0)
        #expect(NormRect.full.aspectRatio == 1.0)
    }

    @Test func sizeInchesAspectRatio() {
        #expect(SizeInches(width: 10, height: 8).aspectRatio == 1.25)
        #expect(SizeInches(width: 8, height: 10).aspectRatio == 0.8)
    }

    @Test func normRectCodableRoundTrip() throws {
        let original = NormRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NormRect.self, from: data)
        #expect(decoded == original)
    }

    @Test func sizeInchesCodableRoundTrip() throws {
        let original = SizeInches(width: 12.5, height: 9.75)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SizeInches.self, from: data)
        #expect(decoded == original)
    }

    @Test func inchLabelFormatsWholeAndFractional() {
        #expect(SizeInches(width: 7, height: 7).inchLabel == "7×7 in")
        #expect(SizeInches(width: 10, height: 8).inchLabel == "10×8 in")
        #expect(SizeInches(width: 8.5, height: 11).inchLabel == "8.5×11 in")
    }

    @Test func centimeterLabelRoundsToWholeCentimetres() {
        #expect(SizeInches(width: 5, height: 5).centimeterLabel == "13×13 cm")
        #expect(SizeInches(width: 7, height: 7).centimeterLabel == "18×18 cm")
        #expect(SizeInches(width: 10, height: 8).centimeterLabel == "25×20 cm")
        #expect(SizeInches(width: 8, height: 10).centimeterLabel == "20×25 cm")
        #expect(SizeInches(width: 12, height: 12).centimeterLabel == "30×30 cm")
        #expect(SizeInches(width: 13, height: 11).centimeterLabel == "33×28 cm")
        #expect(SizeInches(width: 5, height: 8).centimeterLabel == "13×20 cm")
        #expect(SizeInches(width: 6, height: 9).centimeterLabel == "15×23 cm")
        #expect(SizeInches(width: 8.5, height: 11).centimeterLabel == "22×28 cm")
    }

    @Test func a4PortraitCentimeterLabel() {
        #expect(SizeInches(width: 8.2677, height: 11.6929).centimeterLabel == "21×30 cm")
    }

    @Test func dualLabelCombinesInchesAndCentimetres() {
        #expect(SizeInches(width: 7, height: 7).dualLabel == "7×7 in (18×18 cm)")
        #expect(SizeInches(width: 8.5, height: 11).dualLabel == "8.5×11 in (22×28 cm)")
    }
}
