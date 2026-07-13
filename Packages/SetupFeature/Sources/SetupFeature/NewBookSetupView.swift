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
        case bookShape
        case bookFormat
        case style
        case generating
    }

    @State private var step: Step = .source
    @State private var collections: [PhotoCollection] = []
    @State private var availablePhotos: [PhotoRef] = []
    @State private var selectedPhotoIDs: Set<PhotoID> = []
    @State private var bookTitle = String(localized: "My Book", bundle: .module)
    @State private var showFolderImporter = false
    @State private var errorMessage: String?
    @State private var isLimitedAccess = false
    @State private var analyzeImportance = false
    @State private var activeProvider: (any PhotoProvider)?
    @State private var analysisDone = 0
    @State private var analysisTotal = 0
    @State private var selectedPreset: PrintPreset?
    @State private var selectedAspectClass: AspectClass?

    // MARK: Curation step

    @State private var curationModel = CurationStepModel()
    /// Where the curation step's Back button returns to — `.photoGrid` for
    /// the Photos flow, `.source` for the folder flow (which has no grid).
    @State private var curationOrigin: Step = .photoGrid

    public var body: some View {
        VStack(spacing: 0) {
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
            case .bookShape: bookShapeStep
            case .bookFormat: bookFormatStep
            case .style: styleStep
            case .generating:
                ProgressView(analysisTotal > 0 && analysisDone < analysisTotal
                             ? String(localized: "Analyzing photos… (\(analysisDone)/\(analysisTotal))", bundle: .module)
                             : String(localized: "Laying out your book…", bundle: .module))
                    .padding(40)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.025))
        .frame(minWidth: 480, minHeight: 420)
        .fileImporter(isPresented: $showFolderImporter,
                      allowedContentTypes: [.folder]) { result in
            handleFolderPick(result)
        }
    }

    /// Borderless chevron "Back" — the bare push-button looked clunky on macOS.
    private func backButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(String(localized: "Back", bundle: .module), systemImage: "chevron.backward")
        }
        .buttonStyle(.borderless)
        .help(Text("Go back to the previous step", bundle: .module))
    }

    // MARK: Step 1 — source

    private var sourceStep: some View {
        VStack(spacing: 28) {
            setupHeader(step: 1,
                        title: String(localized: "Choose photos", bundle: .module),
                        subtitle: String(localized: "Start with Apple Photos or a folder on this device", bundle: .module)) {
                onExitToWelcome()
            }
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text("Where are your photos?", bundle: .module)
                    .font(.title2.bold())
                HStack(spacing: 20) {
                    Button {
                        loadPhotoCollections()
                    } label: {
                        sourceCard(systemImage: "photo.on.rectangle.angled",
                                   title: String(localized: "From Photos", bundle: .module),
                                   subtitle: String(localized: "Albums from your Apple Photos library", bundle: .module))
                    }
                    .buttonStyle(.plain)
                    .help(Text("Pick photos from your Apple Photos library", bundle: .module))
                    .accessibilityIdentifier("source-photos")

                    Button {
                        showFolderImporter = true
                    } label: {
                        sourceCard(systemImage: "folder",
                                   title: String(localized: "From Folder", bundle: .module),
                                   subtitle: String(localized: "JPEG, HEIC, PNG, TIFF, RAW", bundle: .module))
                    }
                    .buttonStyle(.plain)
                    .help(Text("Pick photos from a folder of image files", bundle: .module))
                    .accessibilityIdentifier("source-folder")
                }
            }
            Spacer()
        }
        .padding(28)
    }

    private func sourceCard(systemImage: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(height: 42)
            Text(title).font(.title3.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Spacer()
            HStack {
                Text("Choose source", bundle: .module).font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.right").font(.caption)
            }
            .foregroundStyle(Color.accentColor)
        }
        .padding(20)
        .frame(width: 240, height: 190)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18)) }
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
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
                    errorMessage = String(localized: "Could not load your Photos albums: \(error.localizedDescription)", bundle: .module)
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
                        errorMessage = String(localized: "No importable images found in \"\(collection.title)\".", bundle: .module)
                        return
                    }
                    bookTitle = collection.title
                    availablePhotos = refs
                    selectedPhotoIDs = Set(refs.map(\.id))   // folder: all auto-selected
                    activeProvider = providers.fileSystem
                    curationModel = defaultCurationModel(availableCount: refs.count)
                    curationOrigin = .source
                    step = .curation
                } catch {
                    errorMessage = String(localized: "Could not read that folder: \(error.localizedDescription)", bundle: .module)
                }
            }
        }
    }

    // MARK: Step 1b — Photos collections + grid

    private var collectionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupHeader(step: 1,
                        title: String(localized: "Choose an album", bundle: .module),
                        subtitle: String(localized: "Select where your story lives", bundle: .module)) {
                step = .source
            }
            limitedAccessBanner
            List(collections) { collection in
                Button {
                    loadPhotos(in: collection)
                } label: {
                    HStack {
                        Text(collection.title)
                        Spacer()
                        if let count = collection.estimatedCount {
                            Text(verbatim: "\(count)").foregroundStyle(.secondary)
                        }
                    }
                }
                .help(Text("Use photos from this album", bundle: .module))
            }
        }
        .padding(28)
    }

    private func loadPhotos(in collection: PhotoCollection) {
        errorMessage = nil
        Task {
            do {
                let refs = try await providers.photoKit.photoRefs(in: collection)
                guard !refs.isEmpty else {
                    errorMessage = String(localized: "\"\(collection.title)\" has no photos.", bundle: .module)
                    return
                }
                bookTitle = collection.title
                availablePhotos = refs
                selectedPhotoIDs = Set(refs.map(\.id))   // all selected; tap to deselect
                activeProvider = providers.photoKit
                step = .photoGrid
            } catch {
                errorMessage = String(localized: "Could not load photos: \(error.localizedDescription)", bundle: .module)
            }
        }
    }

    private var photoGridStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupHeader(step: 1, title: bookTitle, subtitle: String(localized: "Choose the moments to include", bundle: .module)) {
                step = .photoCollections
            }
            limitedAccessBanner
            HStack {
                Text("\(selectedPhotoIDs.count) of \(availablePhotos.count) selected", bundle: .module)
                    .font(.headline)
                Spacer()
                Button(String(localized: "Clear", bundle: .module)) { selectedPhotoIDs.removeAll() }
                    .disabled(selectedPhotoIDs.isEmpty)
                Button(String(localized: "Select all", bundle: .module)) { selectedPhotoIDs = Set(availablePhotos.map(\.id)) }
                    .disabled(selectedPhotoIDs.count == availablePhotos.count)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)], spacing: 10) {
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
                Spacer()
                Button(String(localized: "Continue with \(selectedPhotoIDs.count) photos", bundle: .module)) {
                    curationModel = defaultCurationModel(availableCount: selectedPhotoIDs.count)
                    curationOrigin = .photoGrid
                    step = .curation
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedPhotoIDs.isEmpty)
                .help(Text("Continue to choose how many photos to keep", bundle: .module))
            }
        }
        .padding(28)
    }

    // MARK: Step 1c — curation

    private func defaultCurationModel(availableCount: Int) -> CurationStepModel {
        let model = CurationStepModel(availableCount: availableCount)
        model.unit = .pages
        model.targetValue = 36
        return model
    }

    private var curationStep: some View {
        VStack(spacing: 16) {
            setupHeader(step: 2, title: String(localized: "Refine your selection", bundle: .module),
                        subtitle: String(localized: "Keep every photo or let us build a balanced story", bundle: .module)) {
                step = curationOrigin
            }
            CurationStepView(
                model: curationModel,
                photos: availablePhotos.filter { selectedPhotoIDs.contains($0.id) },
                provider: activeProvider ?? providers.photoKit,
                onUseAll: { step = .bookShape },
                onContinue: { analyzed, picked in
                    availablePhotos = analyzed
                    selectedPhotoIDs = picked
                    step = .bookShape
                }
            )
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                Label(String(localized: "Showing only photos you've granted access to.", bundle: .module),
                      systemImage: "info.circle")
                    .font(.callout)
                Spacer()
                #if os(iOS)
                Button(String(localized: "Manage...", bundle: .module)) { presentLimitedLibraryPicker() }
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

    private var bookShapeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupHeader(step: 3, title: String(localized: "Choose a book shape", bundle: .module),
                        subtitle: String(localized: "Start with the silhouette that best fits your photos", bundle: .module)) {
                step = .curation
            }
            Spacer()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 16)], spacing: 16) {
                ForEach([AspectClass.landscape, .square, .portrait], id: \.rawValue) { aspect in
                    Button {
                        selectedAspectClass = aspect
                        if selectedPreset?.aspectClass != aspect { selectedPreset = nil }
                    } label: {
                        BookShapeCard(aspectClass: aspect,
                                      isSelected: selectedAspectClass == aspect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
            Spacer()
            HStack {
                Text(selectedAspectClass?.displayTitle ?? String(localized: "Select a shape to continue", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Continue", bundle: .module)) { step = .bookFormat }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedAspectClass == nil)
                    .accessibilityIdentifier("setup-shape-continue")
            }
        }
        .padding(28)
    }

    private var bookFormatStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupHeader(step: 4, title: String(localized: "Choose a book size", bundle: .module),
                        subtitle: String(localized: "Now choose the physical scale of your \(selectedAspectClass?.displayTitle.lowercased() ?? String(localized: "book", bundle: .module))", bundle: .module)) {
                step = .bookShape
            }
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(PresetLibrary.all().filter { $0.aspectClass == selectedAspectClass }) { preset in
                        Button {
                            selectedPreset = preset
                        } label: {
                            PresetCard(preset: preset, isCurrent: selectedPreset?.id == preset.id)
                        }
                        .buttonStyle(.plain)
                        .help(Text("Choose this book size", bundle: .module))
                        .accessibilityIdentifier("preset-\(preset.id)")
                    }
                }
                .padding(.bottom, 12)
            }
            HStack {
                if let selectedPreset {
                    Text("\(selectedPreset.displayName) selected", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select a format to continue", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Continue", bundle: .module)) {
                    step = .style
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedPreset == nil)
                .accessibilityIdentifier("setup-format-continue")
            }
        }
        .padding(28)
    }

    private var styleStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            setupHeader(step: 5, title: String(localized: "Make it yours", bundle: .module),
                        subtitle: String(localized: "Choose how your photos should feel on the page", bundle: .module)) {
                step = .bookFormat
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    standoutSpacingPicker
                    edgeStylePicker
                        .help(Text("Framed: photos sit inside a page margin with gaps. Tiled: photos fill to the page edge but keep gaps between them. Borderless: photos tile edge-to-edge with no gaps.", bundle: .module))
                        .accessibilityIdentifier("setup-edge-style-picker")
                }
                .padding(.bottom, 8)
            }
            HStack {
                if let selectedPreset {
                    Text("\(selectedPreset.displayName) · \(edgeStyleDefault.title)", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(String(localized: "Create my book", bundle: .module)) {
                    if let selectedPreset { generate(with: selectedPreset) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedPreset == nil)
                .accessibilityIdentifier("setup-create-book")
            }
        }
        .padding(28)
    }

    /// Book-wide edge style shown as miniature pages, so the spacing choice is
    /// understandable before the book is generated.
    private var edgeStylePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo edges", bundle: .module).font(.headline)
            Text("Choose how photos meet each other and the edge of the page.", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                ForEach(EdgeStyle.allCases, id: \.rawValue) { style in
                    Button {
                        edgeStyleDefault = style
                    } label: {
                        EdgeStyleCard(style: style, isSelected: edgeStyleDefault == style)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.title)
                    .accessibilityValue(edgeStyleDefault == style
                                        ? Text("Selected", bundle: .module)
                                        : Text("Not selected", bundle: .module))
                }
            }
        }
    }

    private var standoutSpacingPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo emphasis", bundle: .module).font(.headline)
            Text("Choose an even rhythm or let the strongest moments lead.", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                Button { analyzeImportance = false } label: {
                    EmphasisCard(emphasized: false, isSelected: !analyzeImportance)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Balanced pages", bundle: .module))
                .accessibilityValue(!analyzeImportance
                                    ? Text("Selected", bundle: .module)
                                    : Text("Not selected", bundle: .module))

                Button { analyzeImportance = true } label: {
                    EmphasisCard(emphasized: true, isSelected: analyzeImportance)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Give standout photos more space", bundle: .module))
                .accessibilityValue(analyzeImportance
                                    ? Text("Selected", bundle: .module)
                                    : Text("Not selected", bundle: .module))
                .accessibilityIdentifier("setup-smart-spacing-toggle")
            }
        }
    }

    // MARK: Step 3 — generate

    private func generate(with preset: PrintPreset) {
        step = .generating
        var selected = availablePhotos.filter { selectedPhotoIDs.contains($0.id) }
        // Keep the complete curated pool attached to the document. Only the
        // selected subset is laid out below; photos left out by curation stay
        // unplaced so they remain visible in the editor tray and can replace
        // any placed photo later.
        let unselected = availablePhotos.filter { !selectedPhotoIDs.contains($0.id) }
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
                var generated = BookEngine().makeBook(title: title, photos: stamped, preset: preset,
                                                      style: chosenStyle, seed: seed)
                generated.photoLibrary.append(contentsOf: unselected)
                return generated
            }.value
            document.mutate({ $0 = book }, undoManager: undoManager)
            // ContentView observes the document: pages are no longer empty,
            // so the setup flow is dismissed in favor of the browser.
        }
    }

    // MARK: - Shared setup chrome

    private func setupHeader(step number: Int, title: String, subtitle: String,
                             onBack: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                backButton(onBack)
                Spacer()
                Text("STEP \(number) OF 5", bundle: .module)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { index in
                        Capsule()
                            .fill(index <= number ? Color.accentColor : Color.secondary.opacity(0.18))
                            .frame(width: index == number ? 28 : 10, height: 6)
                    }
                }
            }
            Divider()
        }
    }
}

private struct BookShapeCard: View {
    let aspectClass: AspectClass
    let isSelected: Bool
    @State private var turnProgress = 0.0
    @State private var isHovered = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            AnimatedBookPreview(aspectRatio: aspectClass.sampleAspectRatio,
                                turnProgress: turnProgress)
            .frame(height: 112)

            VStack(spacing: 3) {
                Text(aspectClass.displayTitle)
                    .font(.headline)
                Text(aspectClass.shapeExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.34 : 0.18),
                              lineWidth: isSelected ? 2 : 1)
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

/// Not `private`: also used by `PresetPickerView`'s format-switch sheet.
extension AspectClass {
    var displayTitle: String {
        switch self {
        case .landscape: String(localized: "Landscape", bundle: .module)
        case .square: String(localized: "Square", bundle: .module)
        case .portrait: String(localized: "Portrait", bundle: .module)
        }
    }

    var sampleAspectRatio: Double {
        switch self {
        case .landscape: 1.42
        case .square: 1
        case .portrait: 0.72
        }
    }

    var shapeExplanation: String {
        switch self {
        case .landscape: String(localized: "Wide and cinematic", bundle: .module)
        case .square: String(localized: "Balanced and versatile", bundle: .module)
        case .portrait: String(localized: "Tall and editorial", bundle: .module)
        }
    }
}

private struct EmphasisCard: View {
    let emphasized: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.07))
                if emphasized {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor.opacity(0.82))
                            .frame(width: 44)
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.65))
                            RoundedRectangle(cornerRadius: 2).fill(Color.indigo.opacity(0.58))
                        }
                    }
                    .padding(7)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(3)
                    }
                } else {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(index == 1 ? Color.orange.opacity(0.65)
                                      : Color.accentColor.opacity(0.62))
                        }
                    }
                    .padding(7)
                }
            }
            .frame(width: 92, height: 68)

            VStack(alignment: .leading, spacing: 3) {
                Text(emphasized ? String(localized: "Emphasize standouts", bundle: .module) : String(localized: "Balanced pages", bundle: .module))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(emphasized
                     ? String(localized: "Strong photos get larger, quieter pages", bundle: .module)
                     : String(localized: "Photos share the page more evenly", bundle: .module))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1)
        }
    }
}

private struct EdgeStyleCard: View {
    let style: EdgeStyle
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pagePreview
                .frame(height: 82)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title).font(.subheadline.weight(.semibold))
                    Text(style.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18),
                        lineWidth: isSelected ? 2 : 1)
        }
    }

    private var pagePreview: some View {
        GeometryReader { proxy in
            let outer: CGFloat = style.hasOuterMargin ? 8 : 0
            let gap: CGFloat = style.keepsGutter ? 4 : 0
            let width = max(0, proxy.size.width - outer * 2)
            let height = max(0, proxy.size.height - outer * 2)
            HStack(spacing: gap) {
                previewTile(color: Color.accentColor.opacity(0.78))
                    .frame(width: max(0, width * 0.57 - gap / 2))
                VStack(spacing: gap) {
                    previewTile(color: Color.orange.opacity(0.72))
                    previewTile(color: Color.indigo.opacity(0.66))
                }
                .frame(width: max(0, width * 0.43 - gap / 2))
            }
            .frame(width: width, height: height)
            .padding(outer)
            .background(Color.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .aspectRatio(1.55, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
    }

    private func previewTile(color: Color) -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [color, color.opacity(0.62)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

private extension EdgeStyle {
    var title: String {
        switch self {
        case .framed: String(localized: "Framed", bundle: .module)
        case .tiled: String(localized: "Tiled", bundle: .module)
        case .borderless: String(localized: "Borderless", bundle: .module)
        }
    }

    var explanation: String {
        switch self {
        case .framed: String(localized: "Margin and space between photos", bundle: .module)
        case .tiled: String(localized: "To the page edge, with space", bundle: .module)
        case .borderless: String(localized: "Edge-to-edge, without gaps", bundle: .module)
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
                .frame(maxWidth: .infinity)
                .aspectRatio(max(ref.aspectRatio, 0.2), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .saturation(isSelected ? 1 : 0.72)
                .opacity(isSelected ? 1 : 0.72)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .padding(8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .help(isSelected ? Text("Selected — click to remove from the book", bundle: .module)
                         : Text("Click to include this photo", bundle: .module))
        .task(id: ref.id) {
            image = try? await provider.thumbnail(for: ref, maxPixelSize: 192)
        }
    }
}
