import Foundation

/// Classifies WebKit navigation errors by domain and code, so the app can tell a
/// load the firewall cancelled on purpose from a load that actually failed.
public enum NavigationFailure {
    /// `NSURLErrorDomain` code -999: the load was cancelled by a newer load.
    static let urlCancelled = (domain: NSURLErrorDomain, code: NSURLErrorCancelled)

    /// `WebKitErrorDomain` code 102, "Frame load interrupted": a `decidePolicyFor`
    /// cancel of a load already in flight, which WebKit reports as a failure. Any
    /// server redirect into a blocked route arrives this way. The domain string is
    /// legacy WebKit, not `WKErrorDomain`.
    static let policyCancelled = (domain: "WebKitErrorDomain", code: 102)

    public static func isCancellation(domain: String, code: Int) -> Bool {
        (domain == urlCancelled.domain && code == urlCancelled.code)
            || (domain == policyCancelled.domain && code == policyCancelled.code)
    }
}
