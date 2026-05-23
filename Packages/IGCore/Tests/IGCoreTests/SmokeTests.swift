import Testing
@testable import IGCore

/// Proves the toolchain is wired end-to-end: Swift Testing discovers and runs,
/// the IGCore module imports, and `swift test` is green. Real component tests
/// (DomainMapper, IGWebClient, Repository, …) replace/join this during
/// implementation.
@Test func coreModuleLoads() {
    #expect(IGCore.version == "0.0.1")
}
