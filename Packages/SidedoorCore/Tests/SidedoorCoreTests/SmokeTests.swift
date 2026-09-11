import Testing
@testable import SidedoorCore

/// Proves the toolchain is wired end-to-end: Swift Testing discovers and runs,
/// the SidedoorCore module imports, and `swift test` is green. Real component tests
/// (DomainMapper, IGWebClient, Repository, …) replace/join this during
/// implementation.
@Test func coreModuleLoads() {
    #expect(SidedoorCore.version == "0.0.1")
}
