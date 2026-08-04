# 44. The command registry behind the keyboard, the palette, and the sheet

Date: 2026-08-04

## Status

Accepted.

## Context

Three surfaces arrive together and each is a claim about the others: the
keyboard map says a chord does something, the palette offers that same
thing by name and prints the chord, and the reference sheet teaches it.
Written separately they drift the way semantics ids drifted before rule
8. The only keyboard layer in the app was `AppShortcuts`, the review
queue's wrapper, serving one screen.

## Decision

### One registry, read three ways

`WaxCommand{id, label, section, activators, enabled, run}` and a
`CommandRegistry` provider hold every verb. The bindings, the palette's
"Actions" group, and the sheet all come from it: a command appears in all
three or in none.

The review queue's own j/k/a/s/u/e keys stay local - a modal editing
grammar for one screen, documented on it, and nine single letters no
other screen could then use. Scoped commands are palette actions by
convention; a screen wanting a key of its own already has `AppShortcuts`.

### `enabled` is never read by the binding map

Bindings built from live state would rebuild the keyboard on every
position tick. The map is a function of which commands exist; each run
checks its own preconditions when the key is pressed. `CommandShortcuts`
is a widget of its own that hands the identical child back down, so a
scope registering or withdrawing rebuilds nothing beneath it.

### A guard makes the binding not match

`CallbackShortcuts` reports a key handled the moment an activator
accepts, before the callback runs, so a guard that returned early inside
the callback would still stop the event dead. That is fatal for guards
whose whole purpose is to hand the key on: the space would never reach
`WidgetsApp`'s shortcuts and the button somebody tabbed to would not be
pressed (WCAG 2.1.1), and Shift+Arrow and Ctrl+Arrow would never reach
`DefaultTextEditingShortcuts`, killing selection and word-jump in every
field in the app. So `AppShortcuts` dispatches from its own
`Focus.onKeyEvent` and reports a declined key *ignored*.

Two guards. A text field keeps its keys, with `whileTyping` the exception
for the palette's Ctrl/Cmd+K. A focused control keeps a bare space, which
the design system's tappables declare by handling `ActivateIntent`.

The shell's layer never autofocuses: it wraps every screen, so grabbing
focus would take it from a field a screen autofocused, and a node that
merely sat in the traversal order would be an empty tab stop in front of
the whole app.

### It mounts in the signed-in scope, not the shell

The player, the queue, the visualizer, car mode, the track list and the
remote are pushed onto the signed-in navigator, so they are the shell's
siblings. A key event walks the ancestors of what holds focus, so a map
inside the shell is dead on all of them - including the full player,
where a transport key is most likely to be pressed. `_SignedInScope`
wraps the chrome and the overlays alike.

### Ten seconds, and one transport verb

Shift with an arrow seeks ten seconds, whatever is playing: the ±15/30
buttons are shaped for a medium and are settings, but an arrow key is a
nudge, and a nudge that travels a different distance depending on what is
playing cannot be aimed. The deck bar's play button and skip buttons now
run `togglePlayback` and `seekBy` rather than copies of them.

The volume keys and mute read `localVolumeAvailableProvider` and
`outputVolumeProvider`, which is what P14 built them for: the gain is
also written by a routed `set-volume` and by the sleep timer's fade.

### A scope is what is on screen

`CommandScope` gates on the ticker mode (the shell disables it on
branches it is not showing) and the route's `isCurrent`, not on widget
lifetime: the shell keeps every visited branch alive, so lifetime alone
would accumulate every album screen anybody had opened. Both signals are
inherited.

Re-registration compares what is *offered* - id, label, section, glyph,
keys - and not what a command does, so a screen rebuilding for unrelated
reasons does not republish. The rule that follows: a scoped `run` reads
the state it acts on rather than closing over it, because the closure
kept may be several rebuilds old.

A sheet opened on the branch navigator counts as covering, so a screen
that needs its commands through its own sheet opens that sheet on the
root navigator. The palette is unaffected - it is a dialog on the root
navigator, which a branch's stack knows nothing about.

### What the palette reaches

Four groups: actions from the registry, places from the shell chrome
(already role-gated), settings from the settings registry, and the
curation areas.

The library half is the search repository, through a shared
`openSearchHit` the search screen now calls too. Hits are taken
round-robin by kind rather than as a flat cut over the kind-ordered
concatenation, which would let several matching artists hide every album
behind them; the endpoint caps per group, so what is drawn is also what
is asked for. Both caps are named rather than silent: the group's last
row is "Search the library for ...", and the settings group's is "All
settings".

Sharing the opener turned up a stale line: search's episode hit was a
`go`, written in P10 before P12 decided the episode's URL, while
ADR-0032 names search as a pusher of the show-less `/episodes/:pid`. It
pushes now. From the palette a `go` there would have been worse than
losing the results - that route is declared beside the podcasts hub, not
beneath it, so it lands with nothing underneath.

Stations are in "Go to" as well, which corrects 4.4: `/library/search`
does not answer for them, since P14 gave the radio chip the directory
instead. The station list is read only once something is typed, and
tuning goes through the hub's own verb.

Enter runs the highlighted row through the field's submit rather than a
bound Return, and the palette asks for focus back first because
submitting a search field drops it by convention. The highlight follows
hover through `onHover`, not `onEnter`: a row that arrives under a
stationary pointer is not a choice, and would pin the highlight where the
palette opens.

Of the four actions the plan names as examples, three ship. "Start scan"
does not: the client has no scan verb at all, so the admin console slice
registers that command when it builds the thing behind it.

## Consequences

The palette and the sheet are keyboard-only doors, which is what the plan
asks for on desktop and web and leaves a phone with neither. Actions only
the palette reaches (car mode, the visualizer, "play on another device")
stay menu-reachable elsewhere.

Every command is a palette row unless it says otherwise, so `label` is a
user-facing string: sentence case, a verb.
