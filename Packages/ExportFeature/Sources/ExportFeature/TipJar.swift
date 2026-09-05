import Foundation
import StoreKit

/// The six consumable tips, Graphic Meat flavoured, cheapest first. Consumables
/// only: nothing is unlocked, so there is nothing to restore or persist.
public enum TipTier: String, CaseIterable, Sendable {
    case coffee, burger, steak, bbq, brisket, cow

    public var productID: String { "com.graphicMeat.PhotoBooks.tip.\(rawValue)" }

    public static let allProductIDs: [String] = allCases.map(\.productID)

    public static func tier(for productID: String) -> TipTier? {
        allCases.first { $0.productID == productID }
    }

    public var emoji: String {
        switch self {
        case .coffee: "☕"
        case .burger: "🍔"
        case .steak: "🥩"
        case .bbq: "🍖"
        case .brisket: "🔥"
        case .cow: "🐄"
        }
    }

    public var title: String {
        switch self {
        case .coffee: String(localized: "Espresso", bundle: .module)
        case .burger: String(localized: "Smash burger", bundle: .module)
        case .steak: String(localized: "Ribeye, medium rare", bundle: .module)
        case .bbq: String(localized: "Family BBQ", bundle: .module)
        case .brisket: String(localized: "Whole brisket", bundle: .module)
        case .cow: String(localized: "Half a cow", bundle: .module)
        }
    }
}

/// StoreKit 2 tip jar for the App Store build. Failure is silent by design:
/// the products may not exist yet in App Store Connect, or the machine may be
/// offline — either way the whole support block just disappears.
@MainActor
@Observable
public final class TipJar {
    public enum State: Equatable {
        case idle
        case loading
        case ready
        case unavailable
        case purchasing(TipTier)
        case thanked(TipTier)
    }

    public private(set) var products: [Product] = []
    public private(set) var state: State = .idle

    /// ponytail: one shared listener for the whole app, not one per instance —
    /// a `Transaction.updates` loop never ends, so a per-window task would leak
    /// a task per document window. Started from `load()` rather than `init` so
    /// the Developer ID build (which shows a donate link, never the jar) never
    /// touches StoreKit at all. Finishing verified consumables here is all the
    /// unfinished-transaction hygiene a tip jar needs.
    @ObservationIgnored private static var updatesListener: Task<Void, Never>?

    public init() {}

    private static func startUpdatesListener() {
        guard updatesListener == nil else { return }
        updatesListener = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
        }
    }

    public func load() async {
        guard state == .idle else { return }
        state = .loading
        Self.startUpdatesListener()
        do {
            let fetched = try await Product.products(for: TipTier.allProductIDs)
            let order = TipTier.allProductIDs
            products = fetched.sorted {
                (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max)
            }
            state = products.isEmpty ? .unavailable : .ready
        } catch {
            products = []
            state = .unavailable
        }
    }

    public func purchase(_ product: Product) async {
        guard let tier = TipTier.tier(for: product.id) else { return }
        state = .purchasing(tier)
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                state = .thanked(tier)
            default:
                // .userCancelled, .pending, unverified — nothing to celebrate.
                state = .ready
            }
        } catch {
            state = .ready
        }
    }
}
