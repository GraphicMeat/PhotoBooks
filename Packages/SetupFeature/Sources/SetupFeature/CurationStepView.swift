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
                    Text("How much of the story should we keep?", bundle: .module)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("We found \(photos.count) photos. Pick a starting point; you can review every choice before creating the book.", bundle: .module)
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
                Button(String(localized: "Keep every photo", bundle: .module)) { onUseAll() }
                    .help(Text("Skip analysis and include every one of these photos in the book", bundle: .module))
                    .accessibilityIdentifier("curation-use-all")
                Spacer()
                Button(String(localized: "Create a balanced selection", bundle: .module)) { selectBestTapped() }
                    .buttonStyle(.borderedProminent)
                    .disabled(photos.isEmpty)
                    .help(Text("Analyze on-device and keep a balanced selection of about \(model.resolvedPhotoCount) photos", bundle: .module))
                    .accessibilityIdentifier("curation-select-best")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var targetControls: some View {
        VStack(spacing: 12) {
                Picker(String(localized: "Measure by", bundle: .module), selection: $model.unit) {
                    Text("Book length", bundle: .module).tag(CurationStepModel.Unit.pages)
                    Text("Photo count", bundle: .module).tag(CurationStepModel.Unit.photos)
                }
                .pickerStyle(.segmented)
                .help(Text("Choose by approximate book length or by how selective the photo edit should be", bundle: .module))
                .onChange(of: model.unit) { _, unit in
                    model.targetValue = unit == .pages ? 36 : 50
                }

                Picker(String(localized: "Story length", bundle: .module), selection: targetSelection) {
                    ForEach(targetChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                    Label(String(localized: "Custom", bundle: .module), systemImage: "slider.horizontal.3").tag(-1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(Text("Choose a suggested length or set an exact custom target", bundle: .module))

                if isCustomTarget {
                    VStack(spacing: 8) {
                        HStack {
                            Text(model.unit == .pages ? String(localized: "Pages", bundle: .module) : String(localized: "Photos", bundle: .module))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: "\(model.targetValue)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        Slider(value: customTargetValue,
                               in: customTargetRange,
                               step: 1)
                            .accessibilityLabel(model.unit == .pages
                                                ? Text("Desired number of pages", bundle: .module)
                                                : Text("Desired number of photos", bundle: .module))
                            .accessibilityValue(Text(verbatim: "\(model.targetValue)"))
                        HStack {
                            Text(verbatim: "\(Int(customTargetRange.lowerBound))")
                            Spacer()
                            Text(verbatim: "\(Int(customTargetRange.upperBound))")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Label(String(localized: "Choose Custom to set an exact value with a slider", bundle: .module),
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
            [(String(localized: "Short", bundle: .module), 20),
             (String(localized: "Standard", bundle: .module), 36),
             (String(localized: "Full story", bundle: .module), 56)]
        case .photos:
            [(String(localized: "Selective", bundle: .module), 25),
             (String(localized: "Balanced", bundle: .module), 50),
             (String(localized: "Inclusive", bundle: .module), 100)]
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
            return String(localized: "About \(model.targetValue) pages · \(model.resolvedPhotoCount) photos", bundle: .module)
        }
        return String(localized: "About \(model.resolvedPhotoCount) photos", bundle: .module)
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
                    Text("Building a balanced selection", bundle: .module)
                        .font(.title3.bold())
                    Text("Comparing moments and looking for the strongest photos. Everything stays on this device.", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)

                HStack {
                    Text("Analyzing photos", bundle: .module)
                    Spacer()
                    Text("\(done) of \(total)", bundle: .module)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(String(localized: "Cancel", bundle: .module)) { model.cancelAnalysis() }
                    .help(Text("Stop analyzing and go back to choose a different target", bundle: .module))
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
            Text("\(model.pickedCount) photos included", bundle: .module)
                .font(.title2.bold())
            Text("Review the selection below. Tap any photo to include or remove it.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended · \(recommendedIDs.filter { model.pickedIDs.contains($0) }.count) selected", bundle: .module)
                            .font(.headline)
                        MasonryReviewLayout(minimumColumnWidth: 116, spacing: 10) {
                            ForEach(recommendedCandidates) { candidate in
                                thumbnail(for: candidate)
                            }
                        }
                    }

                    if !model.leftOutByCluster.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Left out", bundle: .module).font(.headline)
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
                Button(String(localized: "Continue with \(model.pickedCount) photos", bundle: .module)) { onContinue(analyzedPhotos, model.pickedIDs) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.pickedCount == 0)
                    .help(Text("Continue to choose a book format with the picked photos", bundle: .module))
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
