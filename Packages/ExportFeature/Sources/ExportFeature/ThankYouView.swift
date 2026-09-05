import AppSupport
import StoreKit
import SwiftUI

/// The export sheet's final step: the book is written, so this is the one
/// moment the app has earned a little goodwill. Branding, the exported
/// filenames, and a support ask that depends on how this copy was distributed.
struct ThankYouView: View {
    let urls: [URL]
    let tipJar: TipJar
    let onDone: () -> Void

    @Environment(\.supportOffer) private var supportOffer
    @FocusState private var doneFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            GraphicMeatBrand.logo
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("Thank you for making a book with PhotoBooks", bundle: .module)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Text("We hope the experience was great — and the printed book turns out even better.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(urls, id: \.absoluteString) { url in
                Text(url.lastPathComponent)
                    .font(.callout.monospaced())
            }

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

            Link(destination: GraphicMeatBrand.websiteURL) {
                Text(verbatim: "graphicmeat.com")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(Text("Visit graphicmeat.com", bundle: .module))

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
        }
        // Park initial focus on Done: without it the sheet opens with a focus
        // ring on the first tip button, which reads as "preselected".
        .defaultFocus($doneFocused, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The App Store build's tip jar. Silent about failure: if StoreKit has nothing
/// for us (products not live yet, offline, purchases disabled) the whole block
/// disappears rather than showing an error nobody can act on.
private struct TipJarView: View {
    let jar: TipJar

    var body: some View {
        VStack(spacing: 6) {
            switch jar.state {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .unavailable:
                EmptyView()
            case .thanked(let tier):
                Text("🔥 \(tier.emoji) Meat acquired. Thank you!", bundle: .module)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
            case .ready, .purchasing:
                Text("Fuel the grill at Graphic Meat", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(jar.products) { product in
                        tipButton(product)
                    }
                }
            }
        }
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
