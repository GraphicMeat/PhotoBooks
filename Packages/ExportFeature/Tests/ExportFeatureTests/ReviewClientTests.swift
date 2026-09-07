import Foundation
import Testing
@testable import ExportFeature

@Suite(.serialized) struct ReviewClientTests {
    private func client() -> ReviewClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReviewProtocol.self]
        return ReviewClient(endpoint: URL(string: "https://reviews.example.test/submit")!,
                            session: URLSession(configuration: config))
    }

    @Test func sendsOnlyReviewFieldsWithExplicitConsent() async throws {
        ReviewProtocol.status = 201
        let review = WebsiteReview(id: UUID(), rating: 2, text: "Export could be clearer", publicationAllowed: false)
        try await client().submit(review)
        let request = try #require(ReviewProtocol.request)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == review.id.uuidString)
        let body: Data
        if let data = request.httpBody { body = data }
        else {
            let stream = try #require(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(json.keys) == ["id", "rating", "text", "publicationAllowed"])
        #expect(json["rating"] as? Int == 2)
        #expect(json["publicationAllowed"] as? Bool == false)
    }

    @Test func serverFailureIsNotTreatedAsSubmission() async {
        ReviewProtocol.status = 500
        await #expect(throws: (any Error).self) {
            try await client().submit(WebsiteReview(id: UUID(), rating: 5, text: "Great", publicationAllowed: true))
        }
    }

    @Test func refusesInsecureEndpointAndInvalidRating() async {
        let insecure = ReviewClient(endpoint: URL(string: "http://reviews.example.test/submit")!)
        await #expect(throws: (any Error).self) {
            try await insecure.submit(WebsiteReview(id: UUID(), rating: 5, text: "Great", publicationAllowed: false))
        }
        await #expect(throws: (any Error).self) {
            try await client().submit(WebsiteReview(id: UUID(), rating: 0, text: "Invalid", publicationAllowed: false))
        }
    }
}

private final class ReviewProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 201
    nonisolated(unsafe) static var request: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
