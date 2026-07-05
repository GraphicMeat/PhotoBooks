import SwiftUI
import Testing
@testable import EditorFeature

@MainActor
@Suite struct SnackbarTests {

    @Test func actionInvokesHandlerAndDismisses() {
        var fired = false
        var presented = true
        let binding = Binding(get: { presented }, set: { presented = $0 })
        let bar = SnackbarConfig(message: "Select a photo to swap in",
                                 actionTitle: "Cancel",
                                 isPresented: binding) { fired = true }
        bar.performAction()
        #expect(fired == true)
        #expect(presented == false)
    }
}
