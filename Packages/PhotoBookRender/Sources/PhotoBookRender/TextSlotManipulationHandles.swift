import SwiftUI
import PhotoBookCore

/// Interactive move/resize overlay for the selected TEXT slot. Same drag model
/// as `SlotManipulationHandles`, but corners resize width & height
/// independently (`SlotManipulation.resizeFree`) — the box reshapes the wrap
/// area; font size is set separately in the editor.
struct TextSlotManipulationHandles: View {
    let slotID: UUID
    let frame: NormRect
    let renderSize: CGSize
    let pageInsetX: Double
    let pageInsetY: Double
    let neighbors: [NormRect]
    let onPreview: (NormRect?) -> Void
    let onCommit: (NormRect) -> Void

    private let minShortSide = 0.06
    private let snapThreshold = 0.02
    private let handleSize: CGFloat = 14

    @State private var dragStartFrame: NormRect?

    var body: some View {
        let rect = SlotGeometry.rect(for: frame, in: renderSize)
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
                .position(x: rect.midX, y: rect.midY)
                .gesture(moveGesture())

            ForEach(SlotCorner.allCases, id: \.self) { corner in
                handle(at: corner, slotRect: rect)
            }
        }
        .frame(width: renderSize.width, height: renderSize.height, alignment: .topLeading)
    }

    private func handle(at corner: SlotCorner, slotRect: CGRect) -> some View {
        let point = cornerPoint(corner, in: slotRect)
        return RoundedRectangle(cornerRadius: 3)
            .fill(.white)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 2))
            .frame(width: handleSize, height: handleSize)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .position(x: point.x, y: point.y)
            .gesture(resizeGesture(corner: corner))
    }

    private func cornerPoint(_ corner: SlotCorner, in r: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:     return CGPoint(x: r.minX, y: r.minY)
        case .topRight:    return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft:  return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func moveGesture() -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragStartFrame == nil { dragStartFrame = frame }
                let base = dragStartFrame ?? frame
                let moved = SlotManipulation.move(base,
                    byNormDelta: value.translation.width / renderSize.width,
                    value.translation.height / renderSize.height)
                onPreview(snapped(moved))
            }
            .onEnded { value in
                let base = dragStartFrame ?? frame
                let moved = SlotManipulation.move(base,
                    byNormDelta: value.translation.width / renderSize.width,
                    value.translation.height / renderSize.height)
                dragStartFrame = nil
                onPreview(nil)
                onCommit(snapped(moved))
            }
    }

    private func resizeGesture(corner: SlotCorner) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStartFrame == nil { dragStartFrame = frame }
                let base = dragStartFrame ?? frame
                let out = SlotManipulation.resizeFree(base, corner: corner,
                    byNormDelta: value.translation.width / renderSize.width,
                    value.translation.height / renderSize.height,
                    minShortSide: minShortSide)
                onPreview(snapped(out))
            }
            .onEnded { value in
                let base = dragStartFrame ?? frame
                let out = SlotManipulation.resizeFree(base, corner: corner,
                    byNormDelta: value.translation.width / renderSize.width,
                    value.translation.height / renderSize.height,
                    minShortSide: minShortSide)
                dragStartFrame = nil
                onPreview(nil)
                onCommit(snapped(out))
            }
    }

    private func snapped(_ f: NormRect) -> NormRect {
        SlotSnapper.snap(f, pageInsetX: pageInsetX, pageInsetY: pageInsetY,
                         neighbors: neighbors, threshold: snapThreshold)
    }
}
