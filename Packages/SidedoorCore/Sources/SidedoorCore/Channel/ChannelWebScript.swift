/// The per-channel pieces of the injected user script. Plain strings so a channel
/// stays in one file and the composed script can be unit-tested.
public struct ChannelWebScript: Equatable, Sendable {
    /// Hides the channel's navigation and discovery affordances. Installed once
    /// per page in a `<style data-sidedoor>` element.
    public let css: String

    /// JavaScript defining `lockInlineMedia()` and `inlineMediaState()`; see
    /// `FirewallScript`. `nil` when the channel has no inline feed surface, in
    /// which case no `MutationObserver` is installed for it.
    public let inlineMediaHook: String?

    /// Hides every read thread row while the unread filter is on. Installed in
    /// its own `<style data-sidedoor-unread>` element, disabled until the shell
    /// enables it, so the rules need no scoping prefix. `nil` when the channel has
    /// no measured unread marker; the toggle is then not shown.
    public let unreadFilterCSS: String?

    public init(css: String, inlineMediaHook: String? = nil, unreadFilterCSS: String? = nil) {
        self.css = css
        self.inlineMediaHook = inlineMediaHook
        self.unreadFilterCSS = unreadFilterCSS
    }
}
