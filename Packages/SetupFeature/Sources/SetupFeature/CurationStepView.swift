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
    let onBack: () -> Void
    /// Skip curation entirely — identical to today's pre-curation behavior
    /// (whatever's already selected goes straight to the preset step).
    let onUseAll: () -> Void
    let onContinue: (_ analyzedPhotos: [PhotoRef], _ pickedIDs: Set<PhotoID>) -> Void

    /// Refs as returned by `startAnalysis` — carry the importance/salientCenter
    /// stamps `generate()` needs, and back the review grid's thumbnails.
    @State private var analyzedPhotos: [PhotoRef] = []

    private var refsByID: [PhotoID: PhotoRef] {
        Dictionary(uniqueKeysWithValues: analyzedPhotos.map { ($0.id, $0) })
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

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
    }

    // MARK: - Target picking

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Found \(photos.count) photos").font(.title2)

            VStack(alignment: .leading, spacing: 8) {
                Picker("Preset", selection: $model.targetValue) {
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Pick a starting target for how many to keep")

                Stepper("Keep: \(model.targetValue) \(model.unit.rawValue)",
                        value: $model.targetValue, in: 1...max(photos.count, model.targetValue), step: 5)
                    .help("Fine-tune exactly how many to keep")

                Picker("Unit", selection: $model.unit) {
                    Text("Photos").tag(CurationStepModel.Unit.photos)
                    Text("Pages").tag(CurationStepModel.Unit.pages)
                }
                .pickerStyle(.segmented)
                .help("Choose a photo count directly, or a page count the book should roughly fill")

                if model.unit == .pages {
                    Text("≈ \(model.resolvedPhotoCount) photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack {
                backButton { onBack() }
                Spacer()
                Button("Use all photos") { onUseAll() }
                    .help("Skip analysis and include every one of these photos in the book")
                    .accessibilityIdentifier("curation-use-all")
                Button("Select best") { selectBestTapped() }
                    .buttonStyle(.borderedProminent)
                    .disabled(photos.isEmpty)
                    .help("Analyze photos on-device and keep only the best \(model.resolvedPhotoCount)")
                    .accessibilityIdentifier("curation-select-best")
            }
        }
    }

    private func selectBestTapped() {
        Task {
            if let analyzed = await model.startAnalysis(photos: photos, provider: provider) {
                analyzedPhotos = analyzed
            }
        }
    }

    /// Borderless chevron "Back", matching the other wizard steps.
    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.backward")
        }
        .buttonStyle(.borderless)
        .help("Go back to the previous step")
    }

    // MARK: - Analyzing

    private func analyzingView(done: Int, total: Int) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(done), total: Double(max(total, 1))) {
                Text("Analyzing photos… (\(done)/\(total))")
            }
            .padding(.horizontal, 40)
            Button("Cancel") { model.cancelAnalysis() }
                .help("Stop analyzing and go back to choose a different target")
                .accessibilityIdentifier("curation-cancel")
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Review

    private var reviewGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Picked (\(model.pickedCount) of \(model.resolvedPhotoCount))")
                            .font(.headline)
                        LazyVGrid(columns: gridColumns, spacing: 8) {
                            ForEach(model.pickedCandidates) { candidate in
                                thumbnail(for: candidate, isSelected: true)
                            }
                        }
                    }

                    if !model.leftOutByCluster.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Left out").font(.headline)
                            ForEach(model.leftOutByCluster, id: \.clusterID) { group in
                                LazyVGrid(columns: gridColumns, spacing: 8) {
                                    ForEach(group.members) { candidate in
                                        thumbnail(for: candidate, isSelected: false)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            HStack {
                backButton { onBack() }
                Spacer()
                Button("Continue") { onContinue(analyzedPhotos, model.pickedIDs) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.pickedCount == 0)
                    .help("Continue to choose a book format with the picked photos")
                    .accessibilityIdentifier("curation-continue")
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for candidate: CurationCandidate, isSelected: Bool) -> some View {
        if let ref = refsByID[candidate.id] {
            ProviderThumbnailCell(ref: ref, provider: provider, isSelected: isSelected) {
                model.toggle(candidate.id)
            }
        }
    }
}
