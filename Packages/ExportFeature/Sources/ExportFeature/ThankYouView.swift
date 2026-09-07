import AppSupport
import PDFKit
#if os(iOS)
import QuickLook
#endif
import StoreKit
import SwiftUI

/// A four-step celebration. Export actions come first, followed by community
/// and optional support. Done appears on the final step; no scrolling is needed.
struct ThankYouView: View {
    let urls: [URL]
    let tipJar: TipJar
    let onDone: () -> Void

    @Environment(\.supportOffer) private var supportOffer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var doneFocused: Bool
    @AppStorage("photobooks.hasDonated") private var hasDonated = false
    @AppStorage("photobooks.hideDonationRequests") private var hideDonationRequests = false
    @State private var steps = [0, 1, 2, 3]
    @State private var step = 0
    @State private var wantsToDonateAgain = false
    @State private var reviewSelection = ReviewRatingSelection()
    @State private var reviewDraft = ReviewDraft()
    @State private var revealed = false
    @State private var celebrationStart = Date()
    @State private var backgroundPaused = false
    #if os(iOS)
    @State private var selectedFile: URL?
    #endif

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 440
            let contentWidth = min(640, max(0, geometry.size.width - 32))
            let contentHeight = min(680, max(0, geometry.size.height - 32))
            VStack(spacing: compact ? 8 : 16) {
                let layout = compact ? AnyLayout(HStackLayout(spacing: 20)) : AnyLayout(VStackLayout(spacing: 16))
                layout {
                    if !typeSize.isAccessibilitySize && step != 3 && step != 1 {
                        logo(side: compact ? 144 : (step == 0 ? 176 : 144))
                    }
                    stepContent(compact: compact)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: 520, maxHeight: .infinity)
                        .id(step)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                navigation
            }
            .frame(width: contentWidth, height: contentHeight)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .overlay {
                if !reduceMotion && step == 0 {
                    ExportConfetti(start: celebrationStart)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .background {
            CelebrationBackground(paused: backgroundPaused)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .defaultFocus($doneFocused, true)
        #if os(iOS)
        .quickLookPreview($selectedFile)
        #endif
        .task {
            if supportOffer == .tipJar { await tipJar.load() }
        }
        .onChange(of: tipJar.state) { _, state in
            if case .thanked = state { wantsToDonateAgain = false }
        }
        .onAppear {
            if supportOffer == .tipJar && hasDonated && hideDonationRequests { steps = [0, 1, 2] }
            celebrationStart = .now
            withAnimation(reduceMotion ? nil : .spring(duration: 0.85, bounce: 0.5)) {
                revealed = true
            }
        }
    }

    private func logo(side: CGFloat) -> some View {
        Link(destination: GraphicMeatBrand.websiteURL) {
            GraphicMeatBrand.logo
                .resizable()
                .scaledToFit()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .scaleEffect(revealed || reduceMotion ? 1 : 0.45)
                .rotationEffect(.degrees(revealed || reduceMotion ? 0 : -18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Visit graphicmeat.com", bundle: .module))
        .help(Text("Visit graphicmeat.com", bundle: .module))
        .accessibilityIdentifier("export-brand")
    }

    @ViewBuilder
    private func stepContent(compact: Bool) -> some View {
        switch step {
        case 0:
            VStack(spacing: 12) {
                heading("Your book is ready!")
                HStack(spacing: 12) {
                    BookFlipView(urls: urls)
                        .scaleEffect(revealed || reduceMotion ? 1 : 0.7)
                        .rotationEffect(.degrees(revealed || reduceMotion ? 0 : -6))
                    if !urls.isEmpty {
                        ShareLink(items: urls) {
                            Image(systemName: "square.and.arrow.up")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(Text("Share book", bundle: .module))
                        .help(Text("Share book", bundle: .module))
                        .accessibilityIdentifier("export-share")
                    }
                }
                .frame(maxHeight: 210)

                if urls.count == 1, let url = urls.first {
                    ExportedFileLink(url: url)
                } else if !urls.isEmpty {
                    Menu {
                        ForEach(urls, id: \.absoluteString) { url in
                            Button(url.lastPathComponent) {
                                #if os(macOS)
                                NSWorkspace.shared.open(url)
                                #else
                                selectedFile = url
                                #endif
                            }
                        }
                    } label: {
                        Label(String(localized: "Open exported files", bundle: .module), systemImage: "doc.richtext")
                            .frame(minHeight: 44)
                    }
                }
                #if os(macOS)
                Button(String(localized: "Reveal in Finder", bundle: .module)) {
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
                .accessibilityIdentifier("export-reveal")
                #endif
            }
        case 1:
            FeedbackReviewView(appStoreBuild: supportOffer == .tipJar, compact: compact, selection: $reviewSelection, draft: reviewDraft)
        case 2:
            VStack(spacing: 16) {
                heading("Share work meant to be public")
                Text("Printed a book for a public or commercial project? Share only work you have permission to make public. Keep family albums and private photos private.", bundle: .module)
                    .foregroundStyle(.primary.opacity(0.85))
                actionLink("Share a public project on GitHub", url: GraphicMeatBrand.discussionsURL, id: "export-share-book")
                actionLink("Share a public project via email", url: GraphicMeatBrand.shareProjectEmailURL, id: "export-email-album")
            }
            .multilineTextAlignment(.center)
        default:
            VStack(spacing: compact ? 12 : 20) {
                if supportOffer == .tipJar && hasDonated && !wantsToDonateAgain {
                    supporterThanks(compact: compact)
                } else {
                    if case .donate = supportOffer, !compact && !typeSize.isAccessibilitySize {
                        GraphicMeatBrand.donate
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .accessibilityHidden(true)
                    }
                    heading("Thank you for making a book with PhotoBooks")
                    if !compact {
                        Text("Enjoy your book. If you’d like to support PhotoBooks, you can fuel the next chapter.", bundle: .module)
                            .foregroundStyle(.primary.opacity(0.85))
                    }
                    switch supportOffer {
                    case .tipJar:
                        TipJarView(jar: tipJar, compact: compact)

                    case .donate(let url):
                        Link(destination: url) {
                            HStack(spacing: 16) {
                                Text(verbatim: "🥩")
                                    .font(.largeTitle)
                                Text("Buy Graphic Meat a steak", bundle: .module)
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, minHeight: 80)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(DonationButtonStyle(color: TipTier.steak.donationColor))
                        .accessibilityIdentifier("export-donate")
                    }
                }
                if supportOffer == .tipJar && hasDonated {
                    Toggle(String(localized: "Don’t show donation requests again", bundle: .module), isOn: $hideDonationRequests)
                        .font(.callout)
                        .accessibilityIdentifier("export-hide-donations")
                }
            }
            .multilineTextAlignment(.center)
        }
    }

    private func supporterThanks(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 16) {
            if !compact && !typeSize.isAccessibilitySize {
                GraphicMeatBrand.supportThanks
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)
            }
            heading("Thank you for your support!")
            Text("You’ve already supported PhotoBooks. Thank you for helping fuel the next chapter.", bundle: .module)
                .foregroundStyle(.primary.opacity(0.85))
            Text("Would you like to donate again?", bundle: .module)
            Button(String(localized: "Donate again", bundle: .module)) {
                tipJar.prepareForAnotherDonation()
                wantsToDonateAgain = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("export-donate-again")
        }
        .accessibilityIdentifier("export-supporter-thanks")
    }

    private func heading(_ text: String.LocalizationValue) -> some View {
        Text(String(localized: text, bundle: .module))
            .font(.title.bold())
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
    }

    private func actionLink(_ title: String.LocalizationValue, url: URL, id: String) -> some View {
        Link(destination: url) {
            Text(String(localized: title, bundle: .module))
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityIdentifier(id)
    }

    private func completionStepTitle(_ step: Int) -> String {
        switch step {
        case 0: String(localized: "Files", bundle: .module)
        case 1: String(localized: "Feedback", bundle: .module)
        case 2: String(localized: "Share", bundle: .module)
        default: String(localized: "Support", bundle: .module)
        }
    }

    private var navigation: some View {
        VStack(spacing: 8) {
            Divider()
            Label(String(localized: "Export complete", bundle: .module), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .padding(.vertical, 4)
            ExportStepTracker(titles: steps.map(completionStepTitle),
                              current: steps.firstIndex(of: step) ?? 0)
                .padding(.bottom, 8)

            HStack(spacing: 12) {
                if !reduceMotion {
                    Button {
                        backgroundPaused.toggle()
                    } label: {
                        Image(systemName: backgroundPaused ? "play.circle" : "pause.circle")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary.opacity(0.85))
                    .accessibilityLabel(Text(backgroundPaused ? "Resume background animation" : "Pause background animation", bundle: .module))
                    .help(Text(backgroundPaused ? "Resume background animation" : "Pause background animation", bundle: .module))
                    .accessibilityIdentifier("export-background-motion")
                }
                Spacer(minLength: 8)
                if step > 0 {
                    Button(String(localized: "Back", bundle: .module)) {
                        if step == 1 && reviewDraft.writing {
                            reviewDraft.writing = false
                        } else {
                            move(to: steps[max(0, (steps.firstIndex(of: step) ?? 0) - 1)])
                        }
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(reviewDraft.sending)
                    .accessibilityIdentifier("export-back")
                }
                if step == 1 && reviewDraft.writing {
                    ReviewSubmissionButton(draft: reviewDraft, rating: reviewSelection.rating)
                } else if step != steps.last {
                    Button(String(localized: "Next", bundle: .module)) { move(to: steps[min(steps.count - 1, (steps.firstIndex(of: step) ?? 0) + 1)]) }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("export-next")
                } else {
                    Button(String(localized: "Done", bundle: .module), action: onDone)
                        .buttonStyle(.borderedProminent)
                        .frame(minWidth: 44, minHeight: 44)
                        .focused($doneFocused)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("export-done")
                }
            }
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
        .frame(maxWidth: 520)
    }

    private func move(to newStep: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = newStep }
    }
}

/// Slow-moving paper and colour at the edges keep the celebration alive
/// without putting moving decoration behind the reading area.
private struct CelebrationBackground: View {
    let paused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var elapsed: TimeInterval = 0
    @State private var resumedAt = Date()

    private var animating: Bool {
        visible && !paused && !reduceMotion && !reduceTransparency
            && contrast != .increased && scenePhase == .active
    }
    private let colors: [Color] = [.orange, .pink, .yellow, .mint, .purple]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { timeline in
            let time = elapsed + (animating ? timeline.date.timeIntervalSince(resumedAt) : 0)
            Canvas { context, size in draw(in: context, size: size, time: time) }
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: animating) { wasAnimating, isAnimating in
            if wasAnimating { elapsed += Date.now.timeIntervalSince(resumedAt) }
            if isAnimating { resumedAt = .now }
        }
    }

    // A method rather than an inline Canvas closure: Xcode 26.3's type-checker
    // times out on the mixed CGFloat/Double arithmetic when it is one expression.
    private func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        guard !reduceTransparency && contrast != .increased else { return }
        let dark = colorScheme == .dark
        let width = Double(size.width), height = Double(size.height)
        let radius = max(width, height) * 0.65
        // Broad, translucent colour washes, with a clear centre.
        for i in 0..<4 {
            let phase = time * 0.16 + Double(i) * 1.7
            let x = (i.isMultiple(of: 2) ? 0 : width) + sin(phase) * width * 0.08
            let y = (i < 2 ? 0 : height) + cos(phase) * height * 0.06
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [colors[i].opacity(dark ? 0.18 : 0.16), .clear]),
                    center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
        }

        for i in 0..<34 {
            let seed = Double((i * 37 + 11) % 101) / 100
            let phase = Double(i) * 2.39996
            let edge = 0.025 + seed * 0.105
            let x = width * (i.isMultiple(of: 2) ? edge : 1 - edge) + sin(time * 0.3 + phase) * 7
            let y = height * Double((i * 61 + 7) % 103) / 103 + cos(time * 0.22 + phase) * 14
            var paper = context
            let besideText = y > height * 0.3 && y < height * 0.86
            paper.opacity = (dark ? 0.48 : 0.38) * (besideText ? 0.22 : 1)
            paper.translateBy(x: x, y: y)
            paper.rotate(by: .radians(phase + sin(time * 0.24 + phase) * 0.45))
            let color = colors[i % colors.count]
            if i.isMultiple(of: 4) {
                var ribbon = Path()
                ribbon.move(to: CGPoint(x: -5, y: -12))
                ribbon.addCurve(to: CGPoint(x: 5, y: 12),
                                control1: CGPoint(x: 16, y: -6),
                                control2: CGPoint(x: -16, y: 6))
                paper.stroke(ribbon, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            } else {
                paper.fill(Path(roundedRect: CGRect(x: -3, y: -5, width: 6, height: 10), cornerRadius: 1.5),
                           with: .color(color))
            }
        }
    }
}

/// A single finite burst; drawing stops after the pieces leave the sheet.
private struct ExportConfetti: View {
    let start: Date
    @State private var finished = false
    private let colors: [Color] = [.pink, .orange, .yellow, .mint, .cyan, .purple]

    var body: some View {
        TimelineView(.animation(paused: finished)) { timeline in
            Canvas { context, size in
                draw(in: context, size: size, t: timeline.date.timeIntervalSince(start))
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            finished = true
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, t: Double) {
        guard t >= 0, t < 3 else { return }
        let width = Double(size.width), height = Double(size.height)
        for i in 0..<90 {
            let seed = Double((i * 73 + 19) % 101) / 100
            let angle = Double(i) * 2.39996
            let speed = 130 + seed * 230
            let x = width / 2 + cos(angle) * speed * t
            let y = height * 0.43 + sin(angle) * speed * t + 130 * t * t
            var particle = context
            particle.opacity = min(1, (3 - t) * 2)
            particle.translateBy(x: x, y: y)
            particle.rotate(by: .radians(angle + t * (3 + seed * 7)))
            let rect = CGRect(x: -3, y: -5, width: 6, height: 10)
            particle.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[i % colors.count]))
        }
    }
}

// MARK: - Exported file

/// The filename as a link: click opens the file in whatever handles PDFs
/// (Preview, for nearly everyone) — on iOS a Quick Look sheet.
private struct ExportedFileLink: View {
    let url: URL
    @State private var quickLookURL: URL?

    var body: some View {
        Button {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            quickLookURL = url
            #endif
        } label: {
            Label {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .underline()
            } icon: {
                Image(systemName: "doc.richtext")
            }
        }
        .frame(minHeight: 44)
        .buttonStyle(.borderless)
        .foregroundStyle(.tint)
        .help(Text("Open the exported file", bundle: .module))
        .accessibilityIdentifier("export-open-file")
        #if os(iOS)
        .quickLookPreview($quickLookURL)
        #endif
    }
}

// MARK: - Page-flip preview

/// Leafs through the exported PDF's pages on a timer, like thumbing the
/// printed book. Thumbnails come from the exported file itself, so the
/// preview shows exactly what was written, bleed and all.
private struct BookFlipView: View {
    let urls: [URL]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pages: [CGImage?] = []
    @State private var index = 0

    // ponytail: 24 pages is plenty for a loop nobody watches twice, and keeps
    // a 200-page print PDF from rendering 200 thumbnails on a sheet.
    private nonisolated static let pageCap = 24
    private nonisolated static let thumbnailSide: CGFloat = 400

    var body: some View {
        GeometryReader { geometry in
            let available = CGSize(width: max(1, geometry.size.width), height: max(1, geometry.size.height))
            let reference = pages.compactMap { $0 }.first
            let ratio = reference.map { CGFloat($0.width) / CGFloat($0.height) } ?? 0.75
            let pageHeight = min(available.height, available.width / (2 * ratio))
            let pageWidth = pageHeight * ratio
            HStack(spacing: 0) {
                page(at: index, width: pageWidth, height: pageHeight)
                page(at: index + 1, width: pageWidth, height: pageHeight)
                    .id(index)
                    .transition(reduceMotion ? .opacity : .pageFlip)
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay {
                Rectangle()
                    .fill(.black.opacity(0.12))
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.2), radius: 6, y: 4)
            .frame(width: available.width, height: available.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
        .task { pages = await Self.thumbnails(for: urls) }
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                guard !Task.isCancelled else { return }
                if pages.count > 2 {
                    withAnimation(.easeInOut(duration: 0.7)) { index = (index + 2) % pages.count }
                }
            }
        }
    }

    private func page(at position: Int, width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Color.white
            if pages.indices.contains(position), let image = pages[position] {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private static func thumbnails(for urls: [URL]) async -> [CGImage?] {
        await Task.detached(priority: .utility) {
            var images: [CGImage?] = []
            for url in urls {
                guard let document = PDFDocument(url: url), document.pageCount > 0, images.count < pageCap else { continue }
                // A cover sits on the right; never pair pages from different PDFs.
                images.append(nil)
                for pageIndex in 0..<document.pageCount where images.count < pageCap {
                    guard let page = document.page(at: pageIndex) else { continue }
                    let bounds = page.bounds(for: .cropBox)
                    let scale = thumbnailSide / max(bounds.width, bounds.height, 1)
                    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                    #if os(macOS)
                    let thumbnail = page.thumbnail(of: size, for: .cropBox)
                        .cgImage(forProposedRect: nil, context: nil, hints: nil)
                    #else
                    let thumbnail = page.thumbnail(of: size, for: .cropBox).cgImage
                    #endif
                    images.append(thumbnail)
                }
                if !images.count.isMultiple(of: 2) { images.append(nil) }
            }
            return images
        }.value
    }
}

private struct PageFlip: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
            .opacity(1 - abs(angle) / 100)
    }
}

private extension AnyTransition {
    /// The outgoing page swings away around the spine; the next one swings in
    /// behind it.
    static var pageFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: PageFlip(angle: 90), identity: PageFlip(angle: 0)),
            removal: .modifier(active: PageFlip(angle: -90), identity: PageFlip(angle: 0)))
    }
}

// MARK: - Tip jar

/// The App Store build's tip jar. Silent about failure: if StoreKit has nothing
/// for us (products not live yet, offline, purchases disabled) the whole block
/// disappears rather than showing an error nobody can act on.
private struct TipJarView: View {
    let jar: TipJar
    let compact: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 8) {
            switch jar.state {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .unavailable:
                EmptyView()
            case .thanked(let tier):
                HStack(spacing: 10) {
                    TipArtwork(tier: tier, size: 56)
                    Text("Meat acquired. Thank you!", bundle: .module)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            case .ready, .purchasing:
                Text("Fuel the grill at Graphic Meat", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.85))
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(jar.products) { product in
                        tipButton(product)
                    }
                }
                .frame(maxWidth: 500)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.3), value: jar.state)
        .task { await jar.load() }
    }

    @ViewBuilder
    private func tipButton(_ product: Product) -> some View {
        if let tier = TipTier.tier(for: product.id) {
            let isPurchasing = jar.state == .purchasing(tier)
            Button {
                Task { await jar.purchase(product) }
            } label: {
                DonationButtonLabel(tier: tier, price: product.displayPrice, compact: compact)
                    .opacity(isPurchasing ? 0 : 1)
                    .overlay {
                        if isPurchasing { ProgressView().controlSize(.small).tint(.black) }
                    }
            }
            .buttonStyle(DonationButtonStyle(color: tier.donationColor))
            .disabled(jar.state != .ready)
            .help(Text("Send a tip to Graphic Meat", bundle: .module))
            .accessibilityIdentifier("export-tip-\(tier.rawValue)")
        }
    }
}


private struct TipArtwork: View {
    let tier: TipTier
    let size: CGFloat

    var body: some View {
        Image(tier.artworkName, bundle: .module)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

private struct DonationButtonLabel: View {
    let tier: TipTier
    let price: String
    let compact: Bool

    var body: some View {
        let layout = compact ? AnyLayout(HStackLayout(spacing: 6)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            TipArtwork(tier: tier, size: compact ? 40 : 64)
            VStack(spacing: 4) {
                Text(verbatim: tier.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: price)
                    .font(compact ? .callout.bold() : .headline)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(minHeight: compact ? 64 : 112)
        .padding(.horizontal, 8)
        .padding(.vertical, compact ? 4 : 8)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DonationButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(red: 0.16, green: 0.10, blue: 0.12))
            .background(color, in: RoundedRectangle(cornerRadius: 14))
            .brightness(configuration.isPressed ? -0.06 : 0)
            .opacity(isEnabled ? 1 : 0.65)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private extension TipTier {
    var donationColor: Color {
        switch self {
        case .coffee: Color(red: 1, green: 0.82, blue: 0.48)
        case .burger: Color(red: 1, green: 0.70, blue: 0.44)
        case .steak: Color(red: 1, green: 0.63, blue: 0.66)
        case .bbq: Color(red: 0.82, green: 0.72, blue: 1)
        case .brisket: Color(red: 0.65, green: 0.83, blue: 1)
        case .feast: Color(red: 0.65, green: 0.88, blue: 0.73)
        }
    }
}
