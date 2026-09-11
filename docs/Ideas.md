# Ideas

Candidate features beyond 0.1.0, filtered by the account-safety posture in the
README: anything here must be native chrome, or the same local-CSS class as the
unread filter. No scraping, no polling, no private APIs, no user-agent changes.
Nothing on this list is committed to; it is a backlog to brainstorm from.

Brainstormed 2026-09-10 after the `v0.1.0` release.

## Strengthening the firewall thesis

1. **Face ID / passcode gate + app-switcher blur.** The app holds a logged-in DM
   session; anyone with the unlocked phone can read it. Pure native, small, and
   the thing a "private messages" app should obviously have.
2. **Intentional open.** A native sheet on cold launch — "Who are you here for?"
   — listing pinned people (see 4) with a "just checking in" escape hatch. Turns
   "open app, scroll inbox" into "open app, go to a person."
3. **Session budget.** Optional soft timer (e.g. 10 min). When it lapses, a
   dismissible "still here?" veil — no hard lock, just a felt boundary. The same
   mechanism could auto-return from media mode after N minutes so a shared reel
   does not become a rabbit hole.

## Relationship-first

4. **Pinned people.** Remember the thread URLs of a few threads the user
   chooses (a pin button in the top bar while viewing one) and offer them as
   launch targets. Only remembers a URL the user navigated to — no page content
   is read — but the thread ID must stay out of logs and diagnostics per the
   redaction rule.
5. **Hide the inbox's Notes / story bubbles and Requests noise.** The web inbox
   has a Notes tray at the top that is effectively stories. Same class as the
   unread filter: measure the markup on device first, then a local CSS rule.

## Reach

6. **A second Instagram account** as a separate channel. The channel
   architecture already gives each channel its own data store and tab; mostly
   wiring.
7. **A second network that fits the model better than TikTok did.** X
   (`/messages`, block `/home`), LinkedIn messaging, or Messenger web each have
   a DM surface at a distinct route on mobile web. Unmeasured; needs a recon
   pass like the TikTok one before any decision.

## Suggested order

1 first (cheap, obvious, a real gap in a build that keeps a session), then 2 + 4
together — that pair is what makes Sidedoor a phone book for people you care
about rather than a stripped-down Instagram.
