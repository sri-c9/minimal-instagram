/// IGCore — the pure, UI-free logic layer for Minimal Instagram.
///
/// Everything that can be unit-tested without a simulator lives here:
/// session storage, the IG web client, the firewall `DomainMapper`, the
/// repository, the media fetcher, and the domain models. This module must
/// never import SwiftUI/UIKit — the package boundary is what structurally
/// enforces the spec's "pure mapper, one-way dependencies" firewall rule.
///
/// Components are added test-first during implementation; this file only
/// establishes the module so it builds and is importable.
public enum IGCore {
    /// Marketing version of the core module. Bumped as the package evolves.
    public static let version = "0.0.1"
}
