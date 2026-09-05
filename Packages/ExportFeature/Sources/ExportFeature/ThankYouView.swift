import AppSupport
import PDFKit
#if os(iOS)
import QuickLook
#endif
import StoreKit
import SwiftUI

/// The export sheet's final step: the book is written, so this is the one
/// moment the app has earned a little goodwill. Branding, a page-flipping
/// preview of what was just exported, the files, and a support ask that
/// depends on how this copy was distributed.
struct ThankYouView: View {
    let urls: [URL]
    let tipJar: TipJar
    let onDone: () -> Void

    @Environment(\.supportOffer) private var supportOffer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var doneFocused: Bool
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 14) {
            GraphicMeatBrand.logo
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .reveal(revealed, step: 0)

            VStack(spacing: 6) {
                Text("Thank you for making a book with PhotoBooks", bundle: .module)
                    .font(.title2.bold())
                Text("We hope the experience was great — and the printed book turns out even better.", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 400)
            .reveal(revealed, step: 1)

            BookFlipView(urls: urls)
                .reveal(revealed, step: 2)

            VStack(spacing: 4) {
                ForEach(urls, id: \.absoluteString) { url in
                    ExportedFileLink(url: url)
                }
            }
            .reveal(revealed, step: 3)

            Group {
                switch supportOffer {
                case .tipJar:
                    TipJarView(jar: tipJar)
                case .donate(let url):
                    Link(destination: url) {
                        Text("🥩 Buy Graphic Meat a steak", bundle: .module)
                    }
                    .buttonStyle(.borderedProminent)
                    .help(Text("Support development with a donation", bundle: .module))
                    .accessibilityIdentifier("export-donate")
                }
            }
            .reveal(revealed, step: 4)

            Link(destination: GraphicMeatBrand.websiteURL) {
                Text(verbatim: "graphicmeat.com")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(Text("Visit graphicmeat.com", bundle: .module))
            .reveal(revealed, step: 5)

            HStack {
                Button(String(localized: "Done", bundle: .module), action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .focused($doneFocused)
                #if os(macOS)
                Button(String(localized: "Reveal in Finder", bundle: .module)) {
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
                .help(Text("Show the exported files in Finder", bundle: .module))
                .accessibilityIdentifier("export-reveal")
                #else
                if !urls.isEmpty {
                    ShareLink(items: urls) {
                        Label(String(localized: "Share", bundle: .module), systemImage: "square.and.arrow.up")
                    }
                }
                #endif
            }
            .reveal(revealed, step: 6)
        }
        // Park initial focus on Done: without it the sheet opens with a focus
        // ring on the first tip button, which reads as "preselected".
        .defaultFocus($doneFocused, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if reduceMotion {
                revealed = true
            } else {
                withAnimation { revealed = true }
            }
        }
    }
}

// MARK: - Staggered entrance

private struct Reveal: ViewModifier {
    let shown: Bool
    let step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .animation(.spring(duration: 0.55, bounce: 0.25).delay(0.07 * Double(step)), value: shown)
    }
}

private extension View {
    /// Fades and floats the element in, one step after the previous one, so
    /// the sheet builds top-to-bottom instead of popping in whole.
    func reveal(_ shown: Bool, step: Int) -> some View {
        modifier(Reveal(shown: shown, step: step))
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
                    .font(.callout.monospaced())
                    .underline()
            } icon: {
                Image(systemName: "doc.richtext")
            }
        }
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
    @State private var pages: [CGImage] = []
    @State private var index = 0

    // ponytail: 24 pages is plenty for a loop nobody watches twice, and keeps
    // a 200-page print PDF from rendering 200 thumbnails on a sheet.
    private nonisolated static let pageCap = 24
    private nonisolated static let thumbnailSide: CGFloat = 400

    var body: some View {
        ZStack {
            if pages.indices.contains(index) {
                Image(pages[index], scale: 2, label: Text("Page \(index + 1)", bundle: .module))
                    .resizable()
                    .scaledToFit()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    .id(index)
                    .transition(reduceMotion ? .opacity : .pageFlip)
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .task { pages = await Self.thumbnails(for: urls) }
        .task(id: pages.count) {
            guard pages.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.7)) { index = (index + 1) % pages.count }
            }
        }
    }

    private static func thumbnails(for urls: [URL]) async -> [CGImage] {
        await Task.detached(priority: .utility) {
            var images: [CGImage] = []
            for url in urls {
                guard let document = PDFDocument(url: url) else { continue }
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
                    if let thumbnail { images.append(thumbnail) }
                }
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

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 8) {
            switch jar.state {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .unavailable:
                EmptyView()
            case .thanked(let tier):
                Text("🔥 \(tier.emoji) Meat acquired. Thank you!", bundle: .module)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            case .ready, .purchasing:
                Text("Fuel the grill at Graphic Meat", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 8) {
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
                VStack(spacing: 2) {
                    Text(verbatim: "\(tier.emoji) \(tier.title)")
                        .font(.callout)
                        .lineLimit(1)
                    Text(product.displayPrice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .opacity(isPurchasing ? 0 : 1)
                .overlay { if isPurchasing { ProgressView().controlSize(.small) } }
            }
            .buttonStyle(.bordered)
            .disabled(jar.state != .ready)
            .help(Text("Send a tip to Graphic Meat", bundle: .module))
            .accessibilityIdentifier("export-tip-\(tier.rawValue)")
        }
    }
}
