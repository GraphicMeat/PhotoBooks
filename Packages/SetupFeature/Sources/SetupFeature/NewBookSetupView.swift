import AppSupport
import CoreGraphics
import ModelLayer
import PhotoBookCore
import PhotoBookImport
import Photos
import SwiftUI
#if os(iOS)
import PhotosUI   // presentLimitedLibraryPicker(from:) lives in PhotosUI, not Photos
import UIKit
#endif

/// New-document experience, three steps:
///   1. source — Apple Photos (permission → collections → multi-select grid)
///      or a folder (file importer → all images auto-selected),
///   2. preset — cards from `PresetLibrary`, grouped by aspect class,
///   3. generate — `BookEngine.makeBook` off the main actor, then the
///      document is populated and `ContentView` switches to the browser.
public struct NewBookSetupView: View {
    @ObservedObject var document: BookDocument
    let providers: AppProviders
    /// Escapes the setup flow's first step back to `WelcomeView` (the
    /// `ContentView` owns the welcome/setup toggle this clears).
    var onExitToWelcome: () -> Void = {}
    @Environment(\.undoManager) private var undoManager

    public init(document: BookDocument,
                providers: AppProviders,
                onExitToWelcome: @escaping () -> Void = {}) {
        self.document = document
        self.providers = providers
        self.onExitToWelcome = onExitToWelcome
    }

    enum Step {
        case source
        case permissionExplainer
        case photoCollections
        case photoGrid
        case curation
        case preset
        case generating
    }

    @State private var step: Step = .source
    @State private var collections: [PhotoCollection] = []
    @State private var availablePhotos: [PhotoRef] = []
    @State private var selectedPhotoIDs: Set<PhotoID> = []
    @State private var bookTitle = "My Book"
    @State private var showFolderImporter = false
    @State private var errorMessage: String?
    @State private var isLimitedAccess = false
    @State private var analyzeImportance = false
    @State private var activeProvider: (any PhotoProvider)?
    @State private var analysisDone = 0
    @State private var analysisTotal = 0

    // MARK: Curation step

    @State private var curationModel = CurationStepModel()
    /// Where the curation step's Back button returns to — `.photoGrid` for
    /// the Photos flow, `.source` for the folder flow (which has no grid).
    @State private var curationOrigin: Step = .photoGrid

    public var body: some View {
        VStack(spacing: 16) {
            switch step {
            case .source: sourceStep
            case .permissionExplainer:
                PermissionExplainerView(onUseFolder: {
                    step = .source
                    showFolderImporter = true   // the importer is attached to the outer VStack
                })
            case .photoCollections: collectionsStep
            case .photoGrid: photoGridStep
            case .curation: curationStep
            case .preset: presetStep
            case .generating:
                ProgressView(analysisTotal > 0 && analysisDone < analysisTotal
                             ? "Analyzing photos… (\(analysisDone)/\(analysisTotal))"
                             : "Laying out your book…")
                    .padding(40)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 420)
        .fileImporter(isPresented: $showFolderImporter,
                      allowedContentTypes: [.folder]) { result in
            handleFolderPick(result)
        }
    }

    /// Borderless chevron "Back" — the bare push-button looked clunky on macOS.
    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.backward")
        }
        .buttonStyle(.borderless)
        .help("Go back to the previous step")
    }

    // MARK: Step 1 — source

    private var sourceStep: some View {
        VStack(spacing: 0) {
            HStack {
                backButton { onExitToWelcome() }
                    .accessibilityIdentifier("source-back")
                Spacer()
            }
            Spacer()
            VStack(spacing: 20) {
                Text("Where are your photos?")
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    Button {
                        loadPhotoCollections()
                    } label: {
                        sourceCard(systemImage: "photo.on.rectangle.angled", title: "From Photos",
                                   subtitle: "Albums from your Apple Photos library")
                    }
                    .buttonStyle(.plain)
                    .help("Pick photos from your Apple Photos library")
                    .accessibilityIdentifier("source-photos")

                    Button {
                        showFolderImporter = true
                    } label: {
                        sourceCard(systemImage: "folder", title: "From Folder",
                                   subtitle: "JPEG, HEIC, PNG, TIFF, RAW")
                    }
                    .buttonStyle(.plain)
                    .help("Pick photos from a folder of image files")
                    .accessibilityIdentifier("source-folder")
                }
            }
            Spacer()
        }
    }

    private func sourceCard(systemImage: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
            Text(title).font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 200, height: 160)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func loadPhotoCollections() {
        errorMessage = nil
        Task {
            // requestAccess() collapses the status to a Bool (true for full
            // AND limited — Plan 3), so it cannot drive the explainer/banner
            // split: re-read the full status after the request and route
            // through the tested decision function.
            _ = await PhotoKitProvider.requestAccess()
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            switch photosAccessUI(for: status) {
            case .explainer:
                step = .permissionExplainer
            case .proceed, .proceedWithLimitedBanner:
                isLimitedAccess = photosAccessUI(for: status) == .proceedWithLimitedBanner
                do {
                    collections = try await providers.photoKit.collections()
                    step = .photoCollections
                } catch {
                    errorMessage = "Could not load your Photos albums: \(error.localizedDescription)"
                }
            }
        }
    }

    private func handleFolderPick(_ result: Result<URL, any Error>) {
        errorMessage = nil
        switch result {
        case .failure:
            return   // user cancelled
        case .success(let url):
            Task {
                do {
                    let collection = try providers.fileSystem.makeCollection(fromFolder: url)
                    let refs = try await providers.fileSystem.photoRefs(in: collection)
                    guard !refs.isEmpty else {
                        errorMessage = "No importable images found in \"\(collection.title)\"."
                        return
                    }
                    bookTitle = collection.title
                    availablePhotos = refs
                    selectedPhotoIDs = Set(refs.map(\.id))   // folder: all auto-selected
                    activeProvider = providers.fileSystem
                    curationModel = CurationStepModel(availableCount: refs.count)
                    curationOrigin = .source
                    step = .curation
                } catch {
                    errorMessage = "Could not read that folder: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: Step 1b — Photos collections + grid

    private var collectionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose an album").font(.title2)
            limitedAccessBanner
            List(collections) { collection in
                Button {
                    loadPhotos(in: collection)
                } label: {
                    HStack {
                        Text(collection.title)
                        Spacer()
                        if let count = collection.estimatedCount {
                            Text("\(count)").foregroundStyle(.secondary)
                        }
                    }
                }
                .help("Use photos from this album")
            }
            backButton { step = .source }
        }
    }

    private func loadPhotos(in collection: PhotoCollection) {
        errorMessage = nil
        Task {
            do {
                let refs = try await providers.photoKit.photoRefs(in: collection)
                guard !refs.isEmpty else {
                    errorMessage = "\"\(collection.title)\" has no photos."
                    return
                }
                bookTitle = collection.title
                availablePhotos = refs
                selectedPhotoIDs = Set(refs.map(\.id))   // all selected; tap to deselect
                activeProvider = providers.photoKit
                step = .photoGrid
            } catch {
                errorMessage = "Could not load photos: \(error.localizedDescription)"
            }
        }
    }

    private var photoGridStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose photos (\(selectedPhotoIDs.count) selected)").font(.title2)
            limitedAccessBanner
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                    ForEach(availablePhotos) { ref in
                        ProviderThumbnailCell(
                            ref: ref,
                            provider: providers.photoKit,
                            isSelected: selectedPhotoIDs.contains(ref.id)
                        ) {
                            if selectedPhotoIDs.contains(ref.id) {
                                selectedPhotoIDs.remove(ref.id)
                            } else {
                                selectedPhotoIDs.insert(ref.id)
                            }
                        }
                    }
                }
            }
            HStack {
                backButton { step = .photoCollections }
                Spacer()
                Button("Continue") {
                    curationModel = CurationStepModel(availableCount: selectedPhotoIDs.count)
                    curationOrigin = .photoGrid
                    step = .curation
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPhotoIDs.isEmpty)
                .help("Continue to choose how many photos to keep")
            }
        }
    }

    // MARK: Step 1c — curation

    private var curationStep: some View {
        CurationStepView(
            model: curationModel,
            photos: availablePhotos.filter { selectedPhotoIDs.contains($0.id) },
            provider: activeProvider ?? providers.photoKit,
            onBack: { step = curationOrigin },
            onUseAll: { step = .preset },
            onContinue: { analyzed, picked in
                availablePhotos = analyzed
                selectedPhotoIDs = picked
                step = .preset
            }
        )
    }

    // MARK: Limited-library mode (spec: "limited mode functional")

    /// `.limited` (iOS): everything works on the granted subset; this
    /// banner explains why the grid may look sparse, and Manage… reopens
    /// the system's limited-library picker. On macOS limited mode does not
    /// exist: `isLimitedAccess` is never true, so the banner never shows —
    /// and the picker API is iOS-only, hence the #if os.
    @ViewBuilder
    private var limitedAccessBanner: some View {
        if isLimitedAccess {
            HStack {
                Label("Showing only photos you've granted access to.",
                      systemImage: "info.circle")
                    .font(.callout)
                Spacer()
                #if os(iOS)
                Button("Manage...") { presentLimitedLibraryPicker() }
                    .accessibilityIdentifier("limited-access-manage")
                #endif
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("limited-access-banner")
        }
    }

    #if os(iOS)
    private func presentLimitedLibraryPicker() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
    }
    #endif

    // MARK: Step 2 — preset

    @State private var edgeStyleDefault: EdgeStyle = .framed

    /// Entering this step, SwiftUI auto-focuses the first preset card and draws
    /// a system focus ring that reads as a stray selection. Park initial focus
    /// on Back so no card looks pre-selected; Tab still reaches the cards.
    private enum PresetFocus: Hashable { case back }
    @FocusState private var presetFocus: PresetFocus?

    private var presetStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a book format").font(.title2)
            ScrollView {
                ForEach([AspectClass.square, .landscape, .portrait], id: \.rawValue) { aspectClass in
                    let presets = PresetLibrary.all().filter { $0.aspectClass == aspectClass }
                    if !presets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(aspectClass.rawValue.capitalized)
                                .font(.headline)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                                alignment: .leading,
                                spacing: 12
                            ) {
                                ForEach(presets) { preset in
                                    Button {
                                        generate(with: preset)
                                    } label: {
                                        PresetCard(preset: preset)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Create your book in this size")
                                    .accessibilityIdentifier("preset-\(preset.id)")
                                }
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                smartSpacingToggle
                    .help("When on, your most eye-catching photos get more room — fewer photos share their page. Analysis runs at import and takes longer.")
                    .accessibilityIdentifier("setup-smart-spacing-toggle")
                Text("Gives your best photos more room. Takes longer to import.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            edgeStylePicker
                .help("Framed: photos sit inside a page margin with gaps. Tiled: photos fill to the page edge but keep gaps between them. Borderless: photos tile edge-to-edge with no gaps.")
                .accessibilityIdentifier("setup-edge-style-picker")
            backButton { step = availablePhotos.isEmpty ? .source : .photoGrid }
                .focused($presetFocus, equals: .back)
        }
        .defaultFocus($presetFocus, .back)
    }

    /// Book-wide edge-style default. Segmented on macOS; menu picker on iOS.
    private var edgeStylePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Photo edges").font(.subheadline)
            Picker("Photo edges", selection: $edgeStyleDefault) {
                Text("Framed").tag(EdgeStyle.framed)
                Text("Tiled").tag(EdgeStyle.tiled)
                Text("Borderless").tag(EdgeStyle.borderless)
            }
            .labelsHidden()
            #if os(macOS)
            .pickerStyle(.segmented)
            #endif
        }
    }

    /// Smart-spacing opt-in. `.checkbox` style is macOS-only, matching
    /// edgeStylePicker; iOS uses the default switch.
    private var smartSpacingToggle: some View {
        let toggle = Toggle("Analyze photos for smart spacing", isOn: $analyzeImportance)
        #if os(macOS)
        return toggle.toggleStyle(.checkbox)
        #else
        return toggle
        #endif
    }

    // MARK: Step 3 — generate

    private func generate(with preset: PrintPreset) {
        step = .generating
        var selected = availablePhotos.filter { selectedPhotoIDs.contains($0.id) }
        // Toggle OFF must mean no importance-weighted layout even when the
        // curation step already stamped `importance` as a side effect (the
        // engine honors it unconditionally). Strip it; keep `salientCenter`
        // — that feeds gutter-safe cropping, not layout weight.
        if !analyzeImportance {
            for i in selected.indices { selected[i].importance = nil }
        }
        let title = bookTitle
        var style = BookStyle.standard
        style.edgeStyle = edgeStyleDefault
        let chosenStyle = style
        // The curation step already ran this same Vision pre-pass (its refs
        // come back importance-stamped); re-running it here would double the
        // wait for no benefit, so only analyze when something is unstamped.
        let alreadyAnalyzed = !selected.isEmpty && selected.allSatisfy { $0.importance != nil }
        let shouldAnalyze = analyzeImportance && !alreadyAnalyzed
        let provider = activeProvider
        Task {
            // Optional impure pre-pass: stamp content-importance onto the refs
            // so the (pure) engine can give important photos more room.
            var photos = selected
            // activeProvider is always set before the preset step is reachable
            // (in loadPhotos(in:) and handleFolderPick(_:)), so the nil branch
            // here is unreachable; assert in debug to catch a future regression
            // that would otherwise silently skip the opted-in analysis.
            assert(!shouldAnalyze || provider != nil,
                   "smart spacing on but no activeProvider — generate reached without a source")
            if shouldAnalyze, let provider {
                analysisTotal = selected.count
                analysisDone = 0
                photos = await ImageContentAnalyzer.analyze(
                    selected, provider: provider,
                    // total always echoes selected.count (set above); only the
                    // running `done` count needs to flow back to the UI.
                    progress: { done, _ in
                        Task { @MainActor in analysisDone = done }
                    })
            }
            // Immutable snapshot for safe capture in the @Sendable detached task.
            let stamped = photos
            // The engine itself is pure and deterministic; randomness (the
            // seed) lives here in the app layer, per the contract.
            let seed = UInt64.random(in: .min ... .max)
            let book = await Task.detached(priority: .userInitiated) {
                BookEngine().makeBook(title: title, photos: stamped, preset: preset,
                                      style: chosenStyle, seed: seed)
            }.value
            document.mutate({ $0 = book }, undoManager: undoManager)
            // ContentView observes the document: pages are no longer empty,
            // so the setup flow is dismissed in favor of the browser.
        }
    }
}

/// Thumbnail grid cell for the setup flow. Loads straight from the provider
/// (the book — and thus the `ImageStore` — does not exist yet).
struct ProviderThumbnailCell: View {
    let ref: PhotoRef
    let provider: any PhotoProvider
    let isSelected: Bool
    let toggle: () -> Void

    @State private var image: CGImage?

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color(white: 0.85)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(isSelected ? 1 : 0.5)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Selected — click to remove from the book"
                         : "Click to include this photo")
        .task(id: ref.id) {
            image = try? await provider.thumbnail(for: ref, maxPixelSize: 192)
        }
    }
}
