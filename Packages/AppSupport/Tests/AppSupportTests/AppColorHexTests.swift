import Foundation
import Testing
@testable import AppSupport

@Suite struct AppColorHexTests {

    @Test func componentsParsePrimaryAndMixedValues() {
        let red = AppColorHex.components("#FF0000")
        #expect(red?.red == 1 && red?.green == 0 && red?.blue == 0)
        let mixed = AppColorHex.components("#22CC88")
        #expect(mixed.map { abs($0.red - Double(0x22) / 255) < 1e-12 } == true)
        #expect(mixed.map { abs($0.green - Double(0xCC) / 255) < 1e-12 } == true)
        #expect(mixed.map { abs($0.blue - Double(0x88) / 255) < 1e-12 } == true)
    }

    @Test func componentsAcceptLowercaseAndMissingHash() {
        #expect(AppColorHex.components("22cc88") != nil)
        #expect(AppColorHex.components("#22Cc88") != nil)
    }

    @Test func invalidInputReturnsNil() {
        for input in ["", "#FFF", "#GGHHII", "#FFFFFFFF", "not a color"] {
            #expect(AppColorHex.components(input) == nil, "\(input)")
        }
    }

    @Test func hexClampsOutOfRangeComponents() {
        #expect(AppColorHex.hex(red: 1.7, green: -0.4, blue: 0) == "#FF0000")
        #expect(AppColorHex.hex(red: 0, green: 0, blue: 0) == "#000000")
    }

    @Test func everyByteValueRoundTripsExactly() {
        for byte in 0...255 {
            let hex = AppColorHex.hex(red: Double(byte) / 255.0, green: 0, blue: 1)
            let components = AppColorHex.components(hex)
            #expect(components != nil, "\(hex)")
            let back = components.map { AppColorHex.hex(red: $0.red, green: $0.green, blue: $0.blue) }
            #expect(back == hex, "byte \(byte)")
        }
    }
}
