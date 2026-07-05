import Testing
@testable import PhotoBookRender

@Suite struct ColorHexTests {

    @Test func parsesPrimaryColors() {
        let red = ColorHex.components("#FF0000")
        #expect(red.red == 1 && red.green == 0 && red.blue == 0)
        let green = ColorHex.components("#00FF00")
        #expect(green.red == 0 && green.green == 1 && green.blue == 0)
        let blue = ColorHex.components("#0000FF")
        #expect(blue.red == 0 && blue.green == 0 && blue.blue == 1)
    }

    @Test func parsesMixedValueCaseInsensitiveWithOrWithoutHash() {
        for input in ["#22Cc88", "22cc88", "#22CC88"] {
            let c = ColorHex.components(input)
            #expect(abs(c.red - Double(0x22) / 255) < 1e-12, "\(input)")
            #expect(abs(c.green - Double(0xCC) / 255) < 1e-12, "\(input)")
            #expect(abs(c.blue - Double(0x88) / 255) < 1e-12, "\(input)")
        }
    }

    @Test func invalidInputFallsBackToBlack() {
        for input in ["", "#FFF", "#GGHHII", "#FFFFFFFF", "not a color"] {
            let c = ColorHex.components(input)
            #expect(c.red == 0 && c.green == 0 && c.blue == 0, "\(input)")
        }
    }
}
