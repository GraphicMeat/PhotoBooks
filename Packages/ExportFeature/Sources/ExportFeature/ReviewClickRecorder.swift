import Foundation

/// Selecting a lower rating permanently selects the website route for this
/// thank-you flow, including after navigating away and returning.
struct ReviewRatingSelection {
    private(set) var rating = 0
    private(set) var hasSelectedLowerRating = false

    mutating func select(_ value: Int) {
        guard (1...5).contains(value) else { return }
        rating = value
        if value < 5 { hasSelectedLowerRating = true }
    }
}

enum ReviewPromptPolicy {
    static func shouldOfferAppStore(appStoreBuild: Bool, rating: Int, handled: Bool,
                                    hasSelectedLowerRating: Bool = false) -> Bool {
        appStoreBuild && rating == 5 && !handled && !hasSelectedLowerRating
    }
}

struct AppStoreReviewClick: Codable, Sendable {
    let id: UUID
    let type: String
    let rating: Int
    let occurredAt: Date
}

@MainActor enum ReviewClickRecorder {
    private static let key = "photobooks.pendingAppStoreReviewClicks"
    private static var flushing = false

    static func record(rating: Int, defaults: UserDefaults = .standard) {
        var events = pending(defaults: defaults)
        events.append(AppStoreReviewClick(id: UUID(), type: "app_store_review_clicked", rating: rating, occurredAt: .now))
        save(events, defaults: defaults)
    }

    static func pending(defaults: UserDefaults = .standard) -> [AppStoreReviewClick] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AppStoreReviewClick].self, from: data)) ?? []
    }

    static func flush() async {
        guard !flushing,
              let value = Bundle.main.object(forInfoDictionaryKey: "PhotoBooksReviewEventsEndpoint") as? String,
              let endpoint = URL(string: value), endpoint.scheme == "https", endpoint.host != nil else { return }
        flushing = true
        defer { flushing = false }
        for event in pending() {
            do {
                var request = URLRequest(url: endpoint, timeoutInterval: 30)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(event.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                request.httpBody = try encoder.encode(event)
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else { return }
                // Preserve events appended while this request was in flight.
                save(pending().filter { $0.id != event.id }, defaults: .standard)
            } catch { return } // Durable retry on the next feedback visit.
        }
    }

    private static func save(_ events: [AppStoreReviewClick], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: key)
    }
}
