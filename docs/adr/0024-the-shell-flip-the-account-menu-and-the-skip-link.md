# 24. The shell flip, the account menu, and the skip link

Date: 2026-07-26

## Status

Accepted. Amends ADR-0022.

## Context

ADR-0022 built the adaptive shell behind `WAXDECK_NEW_SHELL` and said the
flag existed only across the shell's development window. Two things were
written into this change on purpose when it went up.

**Compact had no way to reach anything that is not a domain.** The
sidebar lists the secondary destinations and the rail reaches them
through one overflow menu, but a phone's tab bar holds the domains and
nothing else. The screens' own app-bar row — seven icon buttons and a
popup menu on the library grid — was left standing for exactly that
reason, and deleting it is what this change does.

**There was no skip-to-content link.** 9.2 asks for one. The frame had
one until it was proved dead: it sat in the shell route's focus scope
while the branch navigator's route owns focus from the first frame, so
Tab never reached it, and it was absent from the semantics tree besides.
ADR-0022 recorded that a working one has to sit in the scope that holds
focus — the page scaffold — or behind a traversal group spanning chrome
and content, and left the verdict to this phase's accessibility pass.

## Decision

**The flag is gone, and so is the flat table.** `shellRoutes()` is the
signed-in table. `newShellProvider`, `waxNewShellDefault`, and
`signedInRoutes` are deleted, `routed_host.dart` mounts one table, and
`route_table_test.dart` drives one navigation. The library grid's app-bar
row and its eleven curation entries go with them, along with the
eighteen identifiers they carried; the specs that steered by those move
to the chrome's own handles in this change.

**The account menu is the compact route to everything that is not a
domain, and it is chrome rather than an app bar.** `WaxAccountButton`
takes the account, the destinations the surrounding chrome does *not*
list, and the account's own actions, and reports the two apart: a
destination is a place and signing out is not. The frame places it and
decides what it carries, because the frame is what knows the size class:

- compact, a fixed cell at the trailing end of the tab bar, carrying
  every secondary destination plus the actions;
- medium, under the rail's overflow, which lists the destinations
  already, so the menu carries the account alone;
- expanded and wide, in the sidebar's footer beside the collapse toggle,
  on the same terms.

3.2 puts the avatar in the top app bar, and that is where it belongs once
the screens are rebuilt on `WaxScaffold` — the shell owns no app bar, and
the screens that do are still the ones written before the design system
existed. The tab bar is the one piece of compact chrome the shell owns
today, so that is where it goes. Its cell is a fixed width rather than an
equal share, so a fifth domain does not squeeze it; a fifth domain plus
an account cell is six targets on a phone, which is one too many, and the
audiobooks phase inherits that count question along with the tab.

**A monogram, not a glyph.** The vendored icon set has no person mark and
adding one is a network-bound asset rebuild; the first letter of the name
on a tinted disc is the more personal answer anyway, and the design
language already uses a monogram where artwork is missing. A name with no
letters in it falls back to the listener glyph rather than an empty
circle.

**The skip link is first in the reading order, not in tab order.** It is
rendered by the frame, painted over the chrome so a focused link is
visible, and sorted ahead of everything else so it is the first node a
screen reader walks and the first element the web build lays out. Both
halves carry an `OrdinalSortKey`: a sort key orders a node only against
siblings whose keys are compatible, and geometry decides the rest, so
keying one of the two would have left the order to whichever rectangle a
knot sort happened to walk first.

That is the order that matters, because it is the order in which the
chrome comes before the content. Tab runs the other way: a route owns
focus from its first frame, so a keyboard reaches the page's own
controls, then the link, then the chrome — nothing to skip, and nothing
lost by the link not being first there. Measured on the real build, not
assumed. ADR-0022 recorded the link as unreachable by Tab; that was a
probe artifact (a classifier that reported the link as page content) and
it is corrected here: the link is reached, second.

**The chrome declares its own `focusable`, because excluding semantics
drops it.** One node per control is the contract the suite and assistive
tech steer by, and `excludeSemantics: true` is what enforces it — but
what it drops is the `Focus` widget's own semantics, and the `focusable`
flag lives there. Web turns that flag into a `tabindex`, so every
destination, the account menu, the collapse toggle, and the skip link
rendered, announced, and carried `tabindex=null`: the entire navigation
was unreachable from a keyboard. The pattern predates this change, but
the flip is what made this chrome the only way around the app. Each node
now declares `focusable`, `focused`, and an `onFocus` that lands the
platform's request on a focus node the item owns.

Activation is by Space, which is the key a `role=button` takes. Enter
activates in the framework and does not survive the web engine's key
routing; the asymmetry is recorded rather than fought.

**So compact gets no skip link.** A phone reads the content first and its
tabs last. A link that skips forward to what is already first is noise in
a screen reader's path, so the frame draws one only where the chrome
precedes the content.

**The content pane is a focus scope with `parentScope` at its edge.** The
link needs somewhere to send focus, and a scope is what gives it one.
`FocusScopeNode` defaults to a closed loop, which would have trapped tab
traversal inside the page and put the whole sidebar out of a keyboard's
reach — the regression is invisible to a golden, so a test tabs out of a
routed pane and fails without the edge behaviour. Skipping asks the
traversal policy where the page starts rather than focusing the scope
itself: a scope with nothing focused takes the focus, which leaves the
visitor one keystroke from the content, and that keystroke is the one the
control exists to save.

## Consequences

- ADR-0022's consequence that the secondary destinations are reached from
  the screens' own app bars on compact is superseded: they are reached
  from the account menu, and the row is gone.
- ADR-0022's consequence that there is no skip-to-content link is
  superseded. The requirement 9.2 states is met where a skip link means
  anything; the page-scaffold placement it named would have put the link
  *after* the sidebar in the reading order, which is the wrong end of
  the problem.
- **The link is painted last and must not swallow the corner it covers.**
  Its box is roughly 140 by 48 at the start edge, which at rail width
  overhangs the content pane by half its width — where a screen's back
  button sits. Ignoring pointers from inside the detector did not do it:
  the detector's outermost render object is an opaque `MouseRegion`,
  whose `hitTest` answers for the whole box whatever sits beneath it, and
  a stack hit-tests in reverse paint order. The ignore is above the
  detector now, and a test taps a back button under the unfocused box.
- Enter does not activate the chrome on web and Space does. The framework
  honours both; the engine's key routing is where they part. Pinned by
  the `a11y-audit` spec, which focuses a destination by name and presses
  the key that works.
- Signing out from the menu takes no confirmation, matching the settings
  screen's own button. Nothing unwinds the stack by hand either: dropping
  the session moves the router's redirect.
- An administrator's compact account menu is longer than a phone screen
  and scrolls. That is the price of one control reaching eleven curation
  areas, and it goes away as those areas move into an admin console.
- The account menu is the shell's, so it sees the signed-in user and
  nothing else. A profile screen would be its first real destination;
  there is none yet, so the menu names the account and offers sign out.
- The registry lost eighteen identifiers and gained three. Renaming or
  retiring one is a contract change, and the specs that steered by the
  old row moved in this change, which is the rule working as intended
  rather than an exception to it.
