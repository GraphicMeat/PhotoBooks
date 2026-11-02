import AppSupport
import StoreKit
import SwiftUI

/// The step before export: what the sponsor pages are, and that one donation
/// removes them. Supporters who land here (a tip restored just now, or the
/// Stripe link coming back) get thanked instead.
struct SupportOfferView: View {
    let tipJar: TipJar

    @Environment(\.supportOffer) private var supportOffer
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(SupporterStatus.defaultsKey) private var hasDonated = false

    var body: some View {
        VStack(spacing: 16) {
            if hasDonated {
                thanks
            } else {
                explanation
                offer
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            if supportOffer == .tipJar { await tipJar.load() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("export-support-step")
    }

    private var thanks: some View {
        VStack(spacing: 16) {
            if !typeSize.isAccessibilitySize {
                GraphicMeatBrand.supportThanks
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)
            }
            Text("Your exports no longer include sponsor pages.", bundle: .module)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("export-supporter-thanks")
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exports include a page saying the album is sponsored by mailvaultapp.com, after the cover and before the last page. Printed books also get a blank page beside each one to keep your spreads together.", bundle: .module)
                .foregroundStyle(.secondary)
            Text("One donation removes these pages from all your exports for good.", bundle: .module)
                .fontWeight(.semibold)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var offer: some View {
        switch supportOffer {
        case .tipJar:
            TipJarView(jar: tipJar)
        case .donate(let url):
            Link(destination: url) {
                HStack(spacing: 16) {
                    GraphicMeatBrand.donate
                        .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                    Text("Buy Graphic Meat a steak", bundle: .module)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(DonationButtonStyle(color: TipTier.steak.donationColor))
            .accessibilityIdentifier("export-donate")
            Text("After donating, you’ll come back here and the sponsor pages will be gone.", bundle: .module)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Tip jar

/// The App Store build's tip jar.
private struct TipJarView: View {
    let jar: TipJar

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 8) {
            switch jar.state {
            case .idle, .loading:
                ProgressView().controlSize(.small)
            case .unavailable:
                Text("Donations aren’t available right now.", bundle: .module)
                    .foregroundStyle(.secondary)
            case .thanked:
                // The supporter flag is already set: SupportOfferView thanks them.
                EmptyView()
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
                DonationButtonLabel(tier: tier, price: product.displayPrice)
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

    var body: some View {
        VStack(spacing: 6) {
            TipArtwork(tier: tier, size: 64)
            VStack(spacing: 4) {
                Text(verbatim: tier.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: price)
                    .font(.headline)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 112)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
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
