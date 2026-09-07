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
