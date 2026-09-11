/// SidedoorCore — the pure, UI-free logic layer for Sidedoor.
///
/// Everything that can be unit-tested without a simulator lives here: the
/// channel definitions, the route firewall, the screen state machine, the
/// injected script composition, and the paused private-API transport. This
/// module must never import SwiftUI, UIKit, or WebKit — the package boundary
/// is what structurally enforces the "pure logic, one-way dependency" rule.
public enum SidedoorCore {
    /// Marketing version of the core module. Bumped as the package evolves.
    public static let version = "0.0.1"
}
