import Foundation

/// Test transport: returns a canned (status, headers, body) and records the last
/// request so tests can assert URL + headers. Install via a URLSessionConfiguration.
final class MockURLProtocol: URLProtocol {
    // swiftlint:disable:next large_tuple
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    // canInit/canonicalRequest are URLProtocol class-method overrides — can't be `static`.
    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }
    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        let (code, headers, body) = MockURLProtocol.responder?(request) ?? (200, [:], Data())
        // swiftlint:disable:next force_unwrapping
        let resp = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
