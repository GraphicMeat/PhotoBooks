import PhotoBookCore
import PhotoBookImport
import SwiftUI

/// Thin bindings over `CurationStepModel` — no logic beyond wiring, per the
/// house convention that testable behavior lives in the model.
struct CurationStepView: View {
    @Bindable var model: CurationStepModel
    /// The pool this step curates: grid-selected refs (Photos flow) or all
    /// imported refs (folder flow).
    let photos: [PhotoRef]
    let provider: any PhotoProvider
    /// Skip curation entirely — identical to today's pre-curation behavior
    /// (whatever's already selected goes straight to the preset step).
    let onUseAll: () -> Void
    let onContinue: (_ analyzedPhotos: [PhotoRef], _ pickedIDs: Set<PhotoID>) -> Void

    /// Refs as returned by `startAnalysis` — carry the importance/salientCenter
    /// stamps `generate()` needs, and back the review grid's thumbnails.
    @State private var analyzedPhotos: [PhotoRef] = []
    /// The curator's original recommendation. Membership in the visual
    /// sections stays stable while the user toggles inclusion on and off.
    @State private var recommendedIDs: Set<PhotoID> = []
    @State private var isCustomTarget = false

    private var refsByID: [PhotoID: PhotoRef] {
        Dictionary(uniqueKeysWithValues: analyzedPhotos.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.phase {
            case .pickingTarget, .cancelled:
                targetPicker
            case .analyzing(let done, let total):
                analyzingView(done: done, total: total)
            case .reviewing:
                reviewGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Target picking

    private var targetPicker: some View {
        VStack(spacing: 14) {
            ScrollView {
                VStack(spacing: 18) {
                    Text("How much of the story should we keep?")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("We found \(photos.count) photos. Pick a starting point; you can review every choice before creating the book.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    bookLengthPreview
                        .frame(height: 142)

                    targetControls
                        .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            }

            Divider()
            HStack {
                Button("Keep every photo") { onUseAll() }
                    .help("Skip analysis and include every one of these photos in the book")
                    .accessibilityIdentifier("curation-use-all")
                Spacer()
                Button("Create a balanced selection") { selectBestTapped() }
                    .buttonStyle(.borderedProminent)
                    .disabled(photos.isEmpty)
                    .help("Analyze on-device and keep a balanced selection of about \(model.resolvedPhotoCount) photos")
                    .accessibilityIdentifier("curation-select-best")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var targetControls: some View {
        VStack(spacing: 12) {
                Picker("Measure by", selection: $model.unit) {
                    Text("Book length").tag(CurationStepModel.Unit.pages)
                    Text("Photo count").tag(CurationStepModel.Unit.photos)
                }
                .pickerStyle(.segmented)
                .help("Choose by approximate book length or by how selective the photo edit should be")
                .onChange(of: model.unit) { _, unit in
                    model.targetValue = unit == .pages ? 36 : 50
                }

                Picker("Story length", selection: targetSelection) {
                    ForEach(targetChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                    Label("Custom", systemImage: "slider.horizontal.3").tag(-1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Choose a suggested length or set an exact custom target")

                if isCustomTarget {
                    VStack(spacing: 8) {
                        HStack {
                            Text(model.unit == .pages ? "Pages" : "Photos")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(model.targetValue)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        Slider(value: customTargetValue,
                               in: customTargetRange,
                               step: 1)
                            .accessibilityLabel(model.unit == .pages
                                                ? "Desired number of pages"
                                                : "Desired number of photos")
                            .accessibilityValue("\(model.targetValue)")
                        HStack {
                            Text("\(Int(customTargetRange.lowerBound))")
                            Spacer()
                            Text("\(Int(customTargetRange.upperBound))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Label("Choose Custom to set an exact value with a slider",
                          systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(selectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
        }
    }

    private var targetChoices: [(label: String, value: Int)] {
        switch model.unit {
        case .pages:
            [("Short", 20), ("Standard", 36), ("Full story", 56)]
        case .photos:
            [("Selective", 25), ("Balanced", 50), ("Inclusive", 100)]
        }
    }

    private var targetSelection: Binding<Int> {
        Binding {
            isCustomTarget ? -1 : model.targetValue
        } set: { value in
            if value == -1 {
                isCustomTarget = true
            } else {
                isCustomTarget = false
                model.targetValue = value
            }
        }
    }

    private var customTargetRange: ClosedRange<Double> {
        switch model.unit {
        case .photos:
            return 1...Double(max(photos.count, 1))
        case .pages:
            // A book page averages roughly 2.5 photos in the paginator. Keep
            // the range useful without offering page counts that cannot add
            // another photo to this import.
            let maximum = max(10, Int(ceil(Double(photos.count) / 2.5)))
            return 10...Double(maximum)
        }
    }

    private var customTargetValue: Binding<Double> {
        Binding {
            Double(model.targetValue).clamped(to: customTargetRange)
        } set: { value in
            model.targetValue = Int(value.rounded())
        }
    }

    private var selectionSummary: String {
        if model.unit == .pages {
            return "About \(model.targetValue) pages · \(model.resolvedPhotoCount) photos"
        }
        return "About \(model.resolvedPhotoCount) photos"
    }

    private var bookLengthPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 222, height: 126)
                .rotationEffect(.degrees(3))
            HStack(spacing: 2) {
                previewPage(reverse: false)
                previewPage(reverse: true)
            }
            .padding(9)
            .background(.background, in: RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.14), radius: 12, y: 7)
        }
        .accessibilityHidden(true)
    }

    private func previewPage(reverse: Bool) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor.opacity(reverse ? 0.50 : 0.78))
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.20))
                RoundedRectangle(cornerRadius: 1).fill(Color.secondary.opacity(0.30))
            }
            .frame(height: model.targetValue >= 50 ? 31 : 22)
        }
        .frame(width: 94, height: 102)
    }

    private func selectBestTapped() {
        Task {
            if let analyzed = await model.startAnalysis(photos: photos, provider: provider) {
                analyzedPhotos = analyzed
                recommendedIDs = model.pickedIDs
            }
        }
    }

    // MARK: - Analyzing

    private func analyzingView(done: Int, total: Int) -> some View {
        VStack {
            Spacer(minLength: 28)
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 74, height: 74)
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 5) {
                    Text("Building a balanced selection")
                        .font(.title3.bold())
                    Text("Comparing moments and looking for the strongest photos. Everything stays on this device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)

                HStack {
                    Text("Analyzing photos")
                    Spacer()
                    Text("\(done) of \(total)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Cancel") { model.cancelAnalysis() }
                    .help("Stop analyzing and go back to choose a different target")
                    .accessibilityIdentifier("curation-cancel")
            }
            .frame(maxWidth: 520)
            .padding(28)
            .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.secondary.opacity(0.14))
            }
            Spacer(minLength: 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Review

    private var reviewGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(model.pickedCount) photos included")
                .font(.title2.bold())
            Text("Review the selection below. Tap any photo to include or remove it.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended · \(recommendedIDs.filter { model.pickedIDs.contains($0) }.count) selected")
                            .font(.headline)
                        MasonryReviewLayout(minimumColumnWidth: 116, spacing: 10) {
                            ForEach(recommendedCandidates) { candidate in
                                thumbnail(for: candidate)
                            }
                        }
                    }

                    if !model.leftOutByCluster.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Left out").font(.headline)
                            MasonryReviewLayout(minimumColumnWidth: 116, spacing: 10) {
                                ForEach(leftOutCandidates) { candidate in
                                    thumbnail(for: candidate)
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Continue with \(model.pickedCount) photos") { onContinue(analyzedPhotos, model.pickedIDs) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.pickedCount == 0)
                    .help("Continue to choose a book format with the picked photos")
                    .accessibilityIdentifier("curation-continue")
            }
        }
    }

    private var recommendedCandidates: [CurationCandidate] {
        model.candidates.filter { recommendedIDs.contains($0.id) }
    }

    private var leftOutCandidates: [CurationCandidate] {
        model.candidates.filter { !recommendedIDs.contains($0.id) }
    }

    @ViewBuilder
    private func thumbnail(for candidate: CurationCandidate) -> some View {
        if let ref = refsByID[candidate.id] {
            ProviderThumbnailCell(ref: ref, provider: provider,
                                  isSelected: model.pickedIDs.contains(candidate.id)) {
                model.toggle(candidate.id)
            }
            .layoutValue(key: PhotoAspectRatioKey.self, value: ref.aspectRatio)
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private struct PhotoAspectRatioKey: LayoutValueKey {
    static let defaultValue = 1.0
}

/// Pinterest-style shortest-column layout, matching the book engine's masonry
/// treatment while keeping each thumbnail at its natural aspect ratio.
private struct MasonryReviewLayout: Layout {
    let minimumColumnWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                     cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumColumnWidth
        return CGSize(width: width, height: arrangement(width: width, subviews: subviews).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX,
                                              y: bounds.minY + frame.minY),
                                  anchor: .topLeading,
                                  proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
        let count = max(1, Int((width + spacing) / (minimumColumnWidth + spacing)))
        let columnWidth = (width - CGFloat(count - 1) * spacing) / CGFloat(count)
        var heights = [CGFloat](repeating: 0, count: count)
        var frames: [CGRect] = []
        for subview in subviews {
            let column = heights.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            let aspect = max(CGFloat(subview[PhotoAspectRatioKey.self]), 0.2)
            let height = columnWidth / aspect
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing),
                                 y: heights[column], width: columnWidth, height: height))
            heights[column] += height + spacing
        }
        return (frames, max(0, (heights.max() ?? 0) - spacing))
    }
}
