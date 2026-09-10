import ModelLayer
import SwiftUI

public extension View {
    /// The entire export flow stays over the main view, from setup to completion.
    func exportFlow(model: ExportModel, editor: BookEditorModel) -> some View {
        modifier(ExportFlowPresentation(model: model, editor: editor))
    }
}

private struct ExportFlowPresentation: ViewModifier {
    let model: ExportModel
    let editor: BookEditorModel

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(model.isFlowPresented)
            .allowsHitTesting(!model.isFlowPresented)
            .overlay {
                if model.isFlowPresented {
                    ExportFlowView(model: model, editor: editor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.background)
                        // An identifier on a container erases every descendant's
                        // own identifier unless the container is declared as one
                        // — without this, "preflight-continue" and friends
                        // vanish from the accessibility tree.
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("export-flow-overlay")
                }
            }
            #if os(macOS)
            .toolbar(model.isFlowPresented ? .hidden : .automatic, for: .windowToolbar)
            #else
            .toolbar(model.isFlowPresented ? .hidden : .automatic, for: .navigationBar)
            #endif
    }
}
