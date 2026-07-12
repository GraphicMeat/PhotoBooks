import PhotoBookCore
import SwiftUI

/// Preset card shared by setup and the format switcher. Hovering plays a
/// physical-book gesture: front cover → open spread → closed back cover.
struct PresetCard: View {
    let preset: PrintPreset
    var isCurrent: Bool = false

    @State private var turnProgress = 0.0
    @State private var isHovered = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 9) {
            AnimatedBookPreview(aspectRatio: preset.trimSize.aspectRatio,
                                turnProgress: turnProgress)
                .frame(height: 88)
            Text(preset.displayName)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            HStack(spacing: 5) {
                Text(preset.trimSize.inchLabel)
                Text("·")
                Text(preset.trimSize.centimeterLabel)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 165)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isCurrent ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.34 : 0.18),
                              lineWidth: isCurrent ? 2 : 1)
        }
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0), radius: 10, y: 5)
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering { playBookAnimation() }
            else { resetBookAnimation() }
        }
        .onDisappear { animationTask?.cancel() }
    }

    private func playBookAnimation() {
        animationTask?.cancel()
        turnProgress = 0
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            for page in 1...4 {
                withAnimation(.easeInOut(duration: 0.72)) { turnProgress = Double(page) }
                try? await Task.sleep(for: .milliseconds(820))
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func resetBookAnimation() {
        animationTask?.cancel()
        animationTask = nil
        withAnimation(.easeOut(duration: 0.24)) { turnProgress = 0 }
    }
}

struct AnimatedBookPreview: View {
    let aspectRatio: Double
    let turnProgress: Double

    var body: some View {
        GeometryReader { proxy in
            // Fit a full open spread inside the preview while preserving the
            // physical page ratio. Capping width after deriving it from a
            // fixed height made landscape formats look almost square.
            let availableHeight = max(1, proxy.size.height - 8)
            let availablePageWidth = max(1, (proxy.size.width - 5) / 2)
            let pageHeight = min(availableHeight, availablePageWidth / max(aspectRatio, 0.01))
            let pageWidth = pageHeight * aspectRatio

            ZStack {
                // The stationary spread establishes a fixed spine. It fades in
                // as the cover begins opening, so the resting state is a single
                // closed book rather than two exposed pages.
                HStack(spacing: 1) {
                    bookPage(kind: .inside, tint: .indigo)
                    bookPage(kind: .inside, tint: .orange)
                }
                .frame(width: pageWidth * 2 + 1, height: pageHeight)
                .opacity(min(1, turnProgress * 2))

                // Four independent sheets share the same leading-edge hinge.
                // Their staggered progress makes each one travel right-to-left
                // across the spine like a physical page.
                ForEach(0..<4, id: \.self) { index in
                    TurningLeaf(
                        front: bookPage(kind: index == 0 ? .front : .inside,
                                        tint: index.isMultiple(of: 2) ? .accentColor : .orange),
                        back: bookPage(kind: .inside,
                                       tint: index.isMultiple(of: 2) ? .indigo : .accentColor),
                        progress: pageProgress(index),
                        size: CGSize(width: pageWidth, height: pageHeight)
                    )
                    .offset(x: pageWidth / 2)
                    .zIndex(Double(10 - index))
                }

                Rectangle()
                    .fill(LinearGradient(colors: [.black.opacity(0.18), .clear, .black.opacity(0.08)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 3, height: pageHeight - 3)
                    .opacity(min(1, turnProgress * 2))
                    .zIndex(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .shadow(color: .black.opacity(0.13), radius: 5, y: 3)
        }
    }

    private func pageProgress(_ index: Int) -> Double {
        min(max(turnProgress - Double(index), 0), 1)
    }

    private enum PageKind { case front, inside }

    private func bookPage(kind: PageKind, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(kind == .inside ? Color.primary.opacity(0.07) : Color.accentColor.opacity(0.13))
            .overlay {
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(LinearGradient(colors: [tint.opacity(kind == .front ? 0.82 : 0.62),
                                                      tint.opacity(0.38)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.16))
                        RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.25))
                    }
                    .frame(height: 17)
                }
                .padding(6)
            }
            .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.22)) }
    }
}

/// A two-sided sheet hinged at its leading edge. Past 90° the back face takes
/// over, avoiding mirrored page artwork while retaining a continuous 3D turn.
private struct TurningLeaf<Front: View, Back: View>: View {
    let front: Front
    let back: Back
    let progress: Double
    let size: CGSize

    var body: some View {
        ZStack {
            front.opacity(progress < 0.5 ? 1 : 0)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(progress >= 0.5 ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            Color.black.opacity(0.13 * sin(.pi * progress))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .rotation3DEffect(.degrees(-180 * progress),
                          axis: (x: 0, y: 1, z: 0),
                          anchor: .leading,
                          perspective: 0.55)
        .shadow(color: .black.opacity(0.22 * sin(.pi * progress)),
                radius: 5, x: -3, y: 2)
    }
}
