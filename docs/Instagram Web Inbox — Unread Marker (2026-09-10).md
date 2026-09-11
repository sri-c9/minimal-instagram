---
title: Sidedoor — Instagram Web Inbox Unread Marker
date: 2026-09-10
status: complete — input to InstagramChannel.unreadFilterCSS (spec §6.11, plan Task 7)
related: "[[Technical Design (V2)]], docs/superpowers/specs/2026-09-09-sidedoor-multi-channel-tiktok-design.md"
---

# Instagram Web Inbox — Unread Marker (2026-09-10)

> **TL;DR.** On Instagram's mobile web inbox (`/direct/inbox/`) an unread thread
> row carries exactly one structural marker: a `span[data-visualcompletion="ignore"]`
> rendered as an 8×8 px dot, containing a screen-reader-only `div` whose text is
> "Unread". Read rows contain no such span, the attribute appears nowhere else in
> the document, and the span is removed from the DOM when the thread is read. The
> thread rows are the `div.html-div` children of one container inside
> `[data-pagelet="IGDInboxThreadListScrollableAreaPagelet"]`, and that scope is
> required: the thread view mounts eleven more elements of the same row shape
> outside the pagelet. A pure-CSS `:not(:has(…))` filter is therefore possible.

**Setup.** iPhone 15 Pro, iOS 26.6. Sidedoor DEBUG build 0.0.1 (1) at commit
`0710727`, `preferredContentMode = .mobile`, per-channel data store. Safari 26.4 on
macOS, Web Inspector attached to the app's `instagram.com` page. Measured with a
console probe that emits DOM shape and counts only (no text, usernames, thread
ids, previews, or hrefs beyond the path prefix); the probe is reproduced in the
appendix. Five runs over ~20 minutes; the unread count moved between runs (5, 1,
4, 3) because messages arrived and were read during the session, which does not
affect the shape findings.

---

## Measured

### The row

- The thread list container is a `div` with the named class `html-div` (plus 25
  hashed classes). Its ancestors up to `<section>` are all hashed-class `div`s
  except: `div[data-pagelet="IGDInboxThreadListScrollableAreaPagelet"]` four
  levels up, and `div[role="navigation"]` with a one-word `aria-label` six levels
  up. `document.title` on the inbox is `"(N) Instagram • Messages"`.
- The container's children (16 on one run, 31 on another) are `div.html-div`
  elements, 72 px tall. Of these, the loaded thread rows have the shape
  `div.html-div > div > div > div[role="button"]` and contain one or two `img`s
  (two for group avatars). The remaining children on the 16-child run were nine
  `div(div(div))` placeholders with no button and no image, and one classless
  `div` holding a `div[role="button"]` directly (shape `div > div[role="button"]`,
  which the row selector below does not match).
- The section header (`h1` "Messages", the "Requests" link) is not a sibling of
  the container; it lives in a separate `html-div` block. `:has(> h1) + div`
  anchoring does not reach the rows. The notes tray's three `div[role="button"]`
  elements (46 hashed classes, contain `img`) share the same pagelet, navigation,
  and section as the row container, so none of those alone excludes them.

### The unread marker

- Each unread row contains exactly one `span[data-visualcompletion="ignore"]` at
  path `div > div > div[role="button"] > div > div > div > div > span` from the row.
  Computed: `display: flex`, `width: 8px`, `height: 8px`,
  `background-color: rgb(74, 93, 249)`, `border-radius: 999px`.
- That span has one child, a `div` (10 hashed classes) whose text content is
  "Unread", with computed `position: absolute; clip: rect(0px, 0px, 0px, 0px);
  width: 1px; height: 1px; overflow: hidden` — a visually hidden accessibility
  label.
- Read rows contain zero `span[data-visualcompletion="ignore"]` elements. The
  attribute appears on no other element in the document: page-wide count of the
  selector equalled the unread-row count on every inbox run (1, 4, 3).
- Unread rows also render their title spans at `font-weight: 600` where read rows
  use 400. Not used: `:has()` cannot select on computed style.

### Counts for the candidate selectors (inbox, run with 7 loaded rows, 4 unread)

| Selector | Total | In list | Of which rows | Outside |
|---|---|---|---|---|
| `span[data-visualcompletion="ignore"]` | 4 | 4 | — | 0 |
| `div[role="button"]:has(img)` | 9 | 6 | 0 (buttons, not rows) | 3 (notes tray) |
| `div.html-div > div.html-div:has(> div > div > div[role="button"] img)` | 6* | 6 | 6 | 0 |
| same, `:not(:has(span[data-visualcompletion="ignore"]))` | 5* | 5 | 5 (all read) | 0 |
| `[data-pagelet="IGDInboxThreadListScrollableAreaPagelet"] div.html-div > div.html-div:has(> div > div > div[role="button"])` | 7 | 7 | 7 | 0 |
| same, `:not(:has(span[data-visualcompletion="ignore"]))` | 3 | 3 | 3 (all read) | 0 |
| same, `:has(span[data-visualcompletion="ignore"])` | 4 | 4 | 4 (all unread) | 0 |

\* from the earlier run with 6 loaded rows and 1 unread. On the 7-row run the
scoped row selector with and without the trailing `img` both counted 7.

### Inside a thread (`/direct/t/N/`)

- The inbox list stays mounted: the scoped row selector still counts 7 and the
  marker spans are still present, collapsed to 0×0 with `display: flex` unchanged.
- The unscoped row-shape selector counts 18 here versus 7 on the inbox: the
  thread view adds eleven elements of the same shape outside the pagelet. The
  pagelet scope is what keeps the filter off them.
- `document.title` inside a thread is the same `"(N) Instagram • Messages"`; no
  thread name.

### Read transition

- Opening the unread thread, then returning to the inbox: the page-wide marker
  count went 4 → 3 and the scoped read-row count 3 → 4, with the row count
  unchanged at 7. The count is of DOM elements, so the marker is removed, not
  hidden.

### The `(N)` in the title

- Present on the inbox and inside a thread. Equal to the scoped unread-row count
  on one of three runs and not on the other two. Not a reliable unread count.

### Native affordances

- No control on the page has text or `aria-label` matching "unread"; the only
  elements whose text matches are the unread rows themselves, via the hidden
  label. The inbox URL carried `__coig_login` and `deoia` query parameters only,
  neither an unread filter.

### With the filter on (device, build with the CSS installed)

- The read rows disappear; the notes tray, header, search field, and the unread
  rows are untouched. One pulsing grey skeleton row (the placeholder shape) sits
  under the last unread row, since the list is now shorter than the viewport.
- Dragging the list upward, even though it cannot scroll, makes Instagram fetch
  the next page: the placeholder resolves into real rows and the read ones
  among them are hidden by the same rule. The skeleton is the lazy-load cue and
  is left visible on purpose.

## Inferred

- The `div(div(div))` placeholders are skeleton rows for threads not yet loaded
  (lazy list). They have no button, so the row selector does not match them and
  the filter leaves them alone; once they load they become real rows and the
  filter applies. Not verified by scrolling during measurement.
- `data-pagelet` values look like stable Meta component identifiers, and the
  `html-div` class is Meta's generic wrapper class rather than a hashed style
  class. Both are assumed to be more stable than the hashed classes. Unverified
  across Instagram releases.
- Bold titles and the dot come and go together; the dot is treated as the single
  source of truth and the weight is ignored.

## Open

- Whether `data-visualcompletion="ignore"` ever appears on another inbox element
  (for example a typing indicator or an "active now" dot) in states not seen
  during this session. Any such element inside a read row would make that row
  count as unread; that is a false negative for the filter, not a hidden thread.
- Message requests (`/direct/requests/`) were not measured.

## Selector written from this document

```css
[data-pagelet="IGDInboxThreadListScrollableAreaPagelet"]
div.html-div > div.html-div:has(> div > div > div[role="button"]):not(:has(span[data-visualcompletion="ignore"])) {
    display: none !important;
}
```

---

## Appendix — the probe (final form)

Run in the Web Inspector console on the app's page. Emits counts and shape only.

```js
(function () {
  const ALLOW = /^(direct|inbox|t|requests|stories|reel|reels|p|explore|accounts|login|onetap|challenge)$/;
  const MARK = 'span[data-visualcompletion="ignore"]';
  const SCOPE = '[data-pagelet="IGDInboxThreadListScrollableAreaPagelet"] ';
  const ROW = 'div.html-div > div.html-div:has(> div > div > div[role="button"])';
  const q = (s) => { try { return document.querySelectorAll(s).length; } catch (e) { return 'INVALID ' + e.message; } };
  console.log(JSON.stringify({
    url: '/' + location.pathname.split('/').filter(Boolean).map(s => ALLOW.test(s) ? s : (/^\d+$/.test(s) ? 'N' : '~')).join('/') + '/',
    title: document.title.replace(/\d+/g, 'N').replace(/[A-Za-z]{2,}/g, w => /instagram|direct|inbox|messages|chats/i.test(w) ? w : 'W'),
    markersOnPage: q(MARK),
    markerState: [...document.querySelectorAll(MARK)].map(m => { const r = m.getBoundingClientRect(); const c = getComputedStyle(m); return { w: Math.round(r.width), h: Math.round(r.height), display: c.display }; }),
    rows: q(SCOPE + ROW),
    readRows: q(SCOPE + ROW + ':not(:has(' + MARK + '))'),
    unreadRows: q(SCOPE + ROW + ':has(' + MARK + ')'),
    rowsUnscoped: q(ROW)
  }, null, 1));
})();
```
