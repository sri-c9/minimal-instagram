import Foundation
import Testing
@testable import SidedoorCore

@Suite("NavigationFailure")
struct NavigationFailureTests {
    @Test func aCancelledURLLoadIsACancellation() {
        #expect(NavigationFailure.isCancellation(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
    }

    @Test func aPolicyInterruptedFrameLoadIsACancellation() {
        #expect(NavigationFailure.isCancellation(domain: "WebKitErrorDomain", code: 102))
    }

    @Test(arguments: [
        ("WKErrorDomain", 102), // the WebKit *framework* domain never carries this code
        ("WebKitErrorDomain", 101),
        (NSURLErrorDomain, NSURLErrorNotConnectedToInternet),
        (NSURLErrorDomain, NSURLErrorTimedOut)
    ])
    func realFailuresAreNotCancellations(domain: String, code: Int) {
        #expect(!NavigationFailure.isCancellation(domain: domain, code: code))
    }
}
