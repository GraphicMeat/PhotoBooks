import AppSupport
import Foundation
import Observation
import StoreKit
import SwiftUI

/// Only typed feedback is sent. Books, photographs, and document metadata are
/// never included. Publication permission is separate and defaults to false.
struct WebsiteReview: Codable, Sendable {
    let id: UUID
    let rating: Int
    let text: String
    let publicationAllowed: Bool
}

struct ReviewClient: Sendable {
    let endpoint: URL
    var session: URLSession = .shared

    func submit(_ review: WebsiteReview) async throws {
        guard endpoint.scheme == "https", (1...5).contains(review.rating),
              !review.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              review.text.count <= 4000 else { throw URLError(.badURL) }
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(review.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(review)
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    static var configured: ReviewClient? {
        guard let string = Bundle.main.object(forInfoDictionaryKey: "PhotoBooksReviewEndpoint") as? String,
              let url = URL(string: string), url.scheme == "https" else { return nil }
        return ReviewClient(endpoint: url)
    }
}

struct FeedbackReviewView: View {
    let appStoreBuild: Bool
    let compact: Bool
    @Binding var selection: ReviewRatingSelection
    @Environment(\.requestReview) private var requestReview
    @AppStorage("photobooks.appStoreReviewHandled") private var appStoreReviewHandled = false
    @Bindable var draft: ReviewDraft
    private var rating: Int { selection.rating }

    var body: some View {
        VStack(spacing: 16) {
            if !draft.writing || !compact {
                Text("How did PhotoBooks work for you?", bundle: .module)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
            }
            if draft.writing {
                reviewForm
            } else {
                Text("Have a feature idea or found a bug? Tell us what would make PhotoBooks better for you.", bundle: .module)
                    .font(.body)
                Link(destination: GraphicMeatBrand.discussionsURL) {
                    Text("Suggest a feature on GitHub", bundle: .module)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("export-suggest-feature")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { bugLinks }
                    VStack(spacing: 8) { bugLinks }
                }
                Divider()
                Text("How would you rate your experience?", bundle: .module)
                    .font(.headline)
                ratingPicker
                if rating > 0 {
                    if draft.websiteSubmitted {
                        Text("Thank you. Your review was received.", bundle: .module)
                    }
                    Button(String(localized: "Write a review", bundle: .module)) {
                        if ReviewPromptPolicy.shouldOfferAppStore(
                            appStoreBuild: appStoreBuild, rating: rating,
                            handled: appStoreReviewHandled,
                            hasSelectedLowerRating: selection.hasSelectedLowerRating
                        ) {
                            // StoreKit cannot confirm submission; persist the
                            // click so this route is not offered again.
                            appStoreReviewHandled = true
                            ReviewClickRecorder.record(rating: rating)
                            requestReview()
                            Task { await ReviewClickRecorder.flush() }
                        } else {
                            draft.writing = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("export-write-review")

                }

            }
        }
        .font(.body)
        .foregroundStyle(.primary)
        .multilineTextAlignment(.center)
        .disabled(draft.sending)
        .task {
            // Preserve suppression chosen in earlier app versions, while
            // allowing website feedback regardless of that preference.
            if UserDefaults.standard.bool(forKey: "photobooks.reviewHandled") {
                appStoreReviewHandled = true
            }
            await ReviewClickRecorder.flush()
        }
        .onChange(of: draft.message) { _, _ in draft.submissionID = UUID() }
        .onChange(of: rating) { _, _ in draft.submissionID = UUID() }
        .onChange(of: draft.publicationAllowed) { _, _ in draft.submissionID = UUID() }
    }

    @ViewBuilder private var bugLinks: some View {
        Link(destination: GraphicMeatBrand.reportBugURL) {
            Text("Report a bug on GitHub", bundle: .module).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        Link(destination: GraphicMeatBrand.reportBugEmailURL) {
            Text("Report a bug via email", bundle: .module).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private var ratingPicker: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Button { selection.select(value) } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .accessibilityLabel(Text("\(value) stars", bundle: .module))
                .accessibilityAddTraits(value == rating ? .isSelected : [])
            }
        }
    }

    private var reviewForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = compact ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your experience", bundle: .module).font(.headline)
                    ratingPicker
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your feedback", bundle: .module).font(.headline)
                    TextEditor(text: $draft.message)
                        .frame(height: compact ? 64 : 100)
                        .padding(4)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.4)))
                        .accessibilityLabel(Text("Your feedback", bundle: .module))
                }
            }
            if !compact {
                Text("Please leave out private information. Maximum 4,000 characters.", bundle: .module)
                    .font(.callout)
            }
            Toggle(isOn: $draft.publicationAllowed) {
                Text("Allow Graphic Meat to publish this feedback on its website.", bundle: .module)
            }
            if draft.failed {
                Text("Couldn’t send your feedback. Your text is still here; please try again.", bundle: .module)
                    .foregroundStyle(.red)
            }

        }
        .multilineTextAlignment(.leading)
    }

}

/// The draft survives form navigation and shares submission state with the flow footer.
@Observable @MainActor
final class ReviewDraft {
    var websiteSubmitted = false
    var writing = false
    var message = ""
    var publicationAllowed = false
    var sending = false
    var failed = false
    var submissionID = UUID()

    func canSubmit(rating: Int) -> Bool {
        rating > 0 && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && message.count <= 4000 && !sending
    }

    func feedbackEmailURL(rating: Int) -> URL {
        var components = URLComponents(string: "mailto:prime@graphicmeat.com")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: "PhotoBooks feedback"),
            URLQueryItem(name: "body", value: "Rating: \(rating)/5\n\n\(message)\n\nPermission to publish: \(publicationAllowed ? "Yes" : "No")")
        ]
        return components.url ?? GraphicMeatBrand.feedbackEmailURL
    }

    func submit(rating: Int) async {
        guard canSubmit(rating: rating), let client = ReviewClient.configured else { return }
        sending = true
        failed = false
        defer { sending = false }
        do {
            try await client.submit(WebsiteReview(id: submissionID, rating: rating,
                text: message.trimmingCharacters(in: .whitespacesAndNewlines), publicationAllowed: publicationAllowed))
            websiteSubmitted = true
            writing = false
        } catch { failed = true }
    }
}

struct ReviewSubmissionButton: View {
    let draft: ReviewDraft
    let rating: Int

    var body: some View {
        HStack(spacing: 8) {
            if draft.sending { ProgressView().controlSize(.small) }
            if ReviewClient.configured != nil {
                Button(String(localized: "Send feedback", bundle: .module)) {
                    Task { await draft.submit(rating: rating) }
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Link(destination: draft.feedbackEmailURL(rating: rating)) {
                    Text("Send feedback via email", bundle: .module)
                }
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(draft.sending || (ReviewClient.configured != nil && !draft.canSubmit(rating: rating)))
        .accessibilityIdentifier("export-send-feedback")
    }
}
