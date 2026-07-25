# 17. Routing is a declared table, and the session is a redirect

Date: 2026-07-25

## Status

Accepted.

## Context

Navigation was imperative: `WaxDeckApp` had a `RootGate` widget that
watched the session probe and returned either the login flow or the
library, and every screen reached the next one with
`Navigator.push(MaterialPageRoute(builder: ...))`. Two deep links
(`/metadata/<pid>`, `/prototype/editing`) were bolted on through
`onGenerateRoute`; nothing else had a URL at all.

That shape blocks the client rewrite in three specific ways.

**No addresses.** On the web build every screen but the two deep links
is unreachable by URL, so nothing can be linked, bookmarked, or reloaded
back into. The plan's adaptive shell also needs the same screen to
render pushed on a phone and in-pane on a desktop, which is a decision
about presentation that cannot live inside 40 call sites.

**Sign-out unwinds by hand.** `SettingsScreen` had to call
`popUntil((route) => route.isFirst)` after logging out, because the gate
only decided what to show at the root. Every future screen that can
invalidate a session would have to remember to do the same.

**A gate is not a redirect.** The gate answered "what widget goes at the
root", so a signed-out visitor with a deep link lost the link, and there
was no single place to state which locations a session may reach.

## Decision

**Adopt `go_router` (exact-pinned) with one declared route table.**
Paths live in `WaxRoute` (`shell/routes.dart`) and screens navigate by
calling them; no screen types a path literal, and no screen calls
`Navigator.push` for a canonical destination. Dialogs, sheets, and menus
stay on `Navigator`/`showDialog`: they are not locations.

**The session is a `redirect`.** One callback decides everything: signed
out goes to `/setup` when the server has no accounts and to `/login`
otherwise, carrying the intended location in a `from` query parameter
that is honored after signing in (validated to be an in-app absolute
path, never a scheme or a protocol-relative host); signed in, the auth
locations are unreachable. `refreshListenable` re-runs it when the
session changes, so signing out replaces the whole signed-in stack
without any screen unwinding by hand.

**The first frame waits for the probes, and only the first.**
`WaxDeckApp`'s builder withholds the `Router` while the session probe
(and, when signed out, the first-run probe) is outstanding, showing the
same spinner the gate did, so the app never routes on a guess it has to
correct a frame later. It then latches: signing out resolves the
first-run probe again, and swapping the router back out for a spinner
would tear down the navigator mid-transition. From there the redirect
owns the outcome, and `refreshListenable` watches both the session and
the first-run probe so a late answer moves a visitor from login to
setup instead of leaving them on the wrong screen. Listening to the
probe costs one cheap call on a signed-in launch; not listening cost
correctness.

**Screens that need more than a URL take it as `extra`, and say so.**
The player, a computed mix list, a browse bucket, the user editor, and
the rule editor are reached with an in-memory payload. `extra` does not
survive a reload or a restored history entry, so each of those routes
carries a redirect that sends a payload-less visit one level up (the
player to the library, a bucket to browse) rather than rendering half a
screen. The alternative, making each one refetch from path parameters,
buys addressability those surfaces do not want: the player is a modal
over what you were doing, and a mix is an answer, not an entity.

**Every signed-in screen is declared under home, not beside it.** A
`go` builds each declared ancestor beneath its target, so a bookmarked
book, a shared metadata link, and the location handed back after a
sign-in all arrive with the library underneath them: a back arrow, and
a system back that goes somewhere instead of out of the app. Declaring
them as siblings would strand every one of those on a single-page
stack. Pushing is unaffected, because a push appends only the branch's
leaf to the stack already there.

**The signed-in shell is a `ShellRoute`.** The sync binder and the share
intake gate wrap it, so the machinery that belongs to a session lives
exactly as long as the session. It is constructed per router rather
than shared from a top-level list: a `ShellRoute` given no key mints
its own navigator `GlobalKey`, and a lazily-initialised top-level
`final` would hand that one key to every router in the process. The
adaptive shell replaces this builder later without touching the table.

**`/prototype/editing` stays outside the session.** It is a rendering
harness with no session of its own and the e2e suite opens it cold.

**The web build keeps the default hash strategy for now.** Path URLs are
a one-line change (`usePathUrlStrategy()`) plus reverse-proxy notes, and
they are deliberately deferred to the end of the rewrite so months of
`/#/...` links in bookmarks and share messages get a redirect shim
rather than a break.

## Consequences

- Every screen is addressable: a typed, shared, or redirected location
  resolves to it, which is what the session redirect and the preserved
  deep links stand on.
- **The address bar tracks `go`, not `push`, and stays that way.**
  In-app taps push (the 1:1 mapping of what they did before), and
  go_router leaves imperative pushes out of the URL it reports unless
  `optionURLReflectsImperativeAPIs` is set. The package advises against
  setting it because a pushed route's URL is not always deep-linkable,
  and WaxDeck is the example: `/now-playing`, `/tracks`, `/remote`,
  `/browse/items`, `/playlists/rules`, and `/admin/users/edit` all need
  an in-memory payload, so putting them in the bar would hand people
  links that resolve to something else. Verified in a browser: pushing
  settings leaves the bar at `/`, a reload from there lands on the grid,
  and browser back still steps through the pushed stack (history entries
  are created per navigation regardless). Per-screen URLs are the
  shell's to deliver, where destination changes are `go` on a branch and
  the payload-carrying screens are overlays on the root navigator;
  `docs/deferred-work.md` carries the entry.
- Presentation is one decision in the table, not 40. Swapping push for
  in-pane at wide widths is a change to the shell, not to screens.
- Declaring screens under home costs a library build beneath a deep
  link that only wanted the metadata editor. That is the price of a
  back affordance on an address someone opened cold, and the shell
  turns home into a tab that was going to be there anyway.
- Widget tests that pump a screen and tap a row need a router: the
  `routedHost` helper mounts one screen over the same `publicRoutes` and
  `signedInRoutes` the app declares, which is why those lists are named
  and exported rather than inlined into the `GoRouter` call.
- `/admin/...` paths carry no role redirect. The menus that lead there
  already hide what an account cannot use and the server refuses the
  calls regardless; a role-aware console shell is the admin phase's job,
  and guessing a path today gets the same refusal it always did.
