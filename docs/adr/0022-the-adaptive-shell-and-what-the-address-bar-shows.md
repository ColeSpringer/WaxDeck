# 22. The adaptive shell, and what the address bar shows

Date: 2026-07-26

## Status

Accepted. The compile-time flag, the old navigation, and the two open
items below (the compact path to the secondary destinations, and the
skip link) are settled by ADR-0024.

## Context

ADR-0017 landed one declared route table and made the session a
redirect, and it left two things open on purpose.

**Navigation lived on one screen's app bar.** Seven icon buttons and a
popup menu on the library grid were the only way to reach browse,
playlists, podcasts, radio, stats, settings, and the eleven curation
areas. Nothing adapted to width: a 1400 px window navigated exactly like
a phone, through a row of unlabelled glyphs.

**The address bar never moved off the last `go`.** Every in-app tap
pushed, and go_router deliberately keeps imperative pushes out of the URL
it reports. Opening settings from the grid left the bar at `/`, so a
reload landed on the grid and there was nothing to share.
`GoRouter.optionURLReflectsImperativeAPIs` is not the fix and the package
says so: half of WaxDeck's pushed routes carry an in-memory payload, and
their URLs resolve to something else on their own.

Both are the shell's to close, and closing them is one decision about
route-table shape rather than two.

## Decision

**`AdaptiveShell` over `StatefulShellRoute.indexedStack`, behind a
compile-time flag.** `--dart-define=WAXDECK_NEW_SHELL=true` selects the
shell and its table; every other build keeps the old navigation. The flag
exists only across the shell's development window and the flip commit
deletes it along with the old navigation, so no long-lived untested
configuration accumulates. A provider reads the flag so a widget test can
mount either shell without a second compilation.

**The frame is a design-system component; the wiring is the app's.**
`WaxShellFrame` picks one piece of chrome per size class - bottom tabs
under 600, a 72 px icon rail to 839, a 248 px sidebar above that, with
the right panel docking only on `wide` - and takes plain view-data
destinations, a content pane, and slots for the deck bar and the panel.
The app supplies destinations, role gating, and the highlight. That keeps
the chrome golden-testable at four widths with no app wiring, and it is
why `waxdeck_ui` still imports nothing but Flutter.

**One branch per domain, and one shared branch for everything else.**
Home, Music, Podcasts, and Radio each get a branch, so a domain's stack
survives a trip to another one and `goBranch` restores it. Settings,
playlists, stats, the metadata editor, and the curation areas share the
last branch. A branch per secondary destination would be the obvious
alternative and it is wrong: `goBranch` restores whatever a branch was
last showing, so a settings visit inside the home branch would become
what the Home tab restores, and a branch of its own for each would
multiply the invalidation fan-out the persistent shell already widens.

**What the address bar shows: `go` where the location's declared parent is
where you already are, `push` everywhere else.** Two questions, in order.
Can a stranger open this location and get this screen? No - an in-memory
payload (`/tracks`, `/remote`, `/browse/items`, `/playlists/rules`,
`/playlists/:pid/edit`, `/admin/users/edit`), or the player, which is a
view of whatever is playing opened over whatever you were doing - then
`push`, and it stays out of the bar because its URL resolves to something
else on its own. Yes, and it is declared under the screen you are on -
then `go`: the ancestry rebuilds beneath it, back lands where a push would
have, and the bar carries a link worth sending.

Yes but declared somewhere else - then `push` as well, because `go` would
rebuild that other ancestry and discard the stack you are standing in.
That is a property of the entry point, not of the route, so the same route
answers differently from different places: a book `go`es from the library
grid (declared under home, which is where the grid is) and is `push`ed
from Browse and from a playlist, where `go` would take a facet bucket
whose contents live in memory and cannot be rebuilt from a URL. The same
holds for `/tasks` from a snackbar (a transient excursion that must return
you to the import or upload that started it), for a review entry opened
from the uploads list rather than from the queue it is declared under, for
`/shares` from a settings row, for `/metadata/:pid` from a review entry,
and for `/episodes/:pid` from its show - an episode's location names no
show, so `go` would build nothing beneath it. Pushing across branches is
sound: go_router renders the pushed page in the branch that declares it
and pops back to the branch you came from, and the branch you left keeps
its stack either way.

**The player, the computed track list, and the remote session are
overlays on the signed-in navigator**, declared beside the shell rather
than inside a branch. They cover the chrome, back closes them, and a push
from any branch reaches the same navigator. The signed-in scope stays
above both, so a player opened cold still has the sync engine, the queue
persister, and playback listening.

**Android back steps once through the shell, through the router's
back-button dispatcher.** From a drilled-in screen the navigators pop as
before; from a domain root other than home the shell switches to home;
from home's own root the press falls through and the app closes.

Not a `PopScope`. One registers with the shell page's route, and
`popRoute` walks the navigator chain from the root down, halting at a
shell navigator whose enclosing route is not current - which is the state
a branch is left in after it has been drilled into and stepped back out
of. In that state the scope is never consulted at all, so back left the
app from a domain root, and a test that only ever visited a branch root
could not see it. A `BackButtonListener` is consulted before that walk
begins, and it reads `canPop` when the press happens rather than during a
build that may not run again.

**The theme is the design system's, app-wide.** `buildWaxTheme` replaces
the seeded `ColorScheme`, and `waxThemeSpecProvider` derives mode, OLED,
and density from the synced preferences: OLED is a parameter of the dark
build rather than a third theme. The bundled family and its fallback
chain moved onto the theme itself, where the tokens' own faces win the
merge, so a bare `TextStyle` in an old screen resolves to the bundled UI
face instead of asking Google's CDN for Roboto.

## Consequences

- The deferred entry on the web address bar is closed. A destination or
  an entity detail is in the bar under both navigations, because the
  `go`/`push` split is a property of the call site rather than of the
  shell; the shell is what makes `go` cheap.
- Both route tables carry every location while the flag exists, and
  `route_table_test.dart` drives the same location list through both. The
  duplication is deliberate and finite: the flip commit deletes the old
  half, which is a subtraction rather than a refactor.
- The chrome's branch list and the router's branches are one contract
  split in two, because `goBranch` takes a number. The same test pins
  them together.
- A domain root has no back affordance, which is correct - a destination
  is not a stack - but it is a change from the old table, where
  everything sat under home. Screens still call `leave()`, which goes
  home when nothing can pop.
- A book lives in the home branch, so opening one from Browse lights
  Home until the audiobooks hub gives books a branch of their own.
- **The highlight falls back to the branch on screen.** Home is the only
  destination that claims a location by being home; every other match is a
  path prefix. So a location nothing else claims - `/episodes/:pid`, and
  anything a later phase adds to a domain branch without putting it under
  the destination's path - lights the domain whose branch is rendering it,
  rather than lighting Home while the podcasts branch is on screen. The
  router's branch index is the authority there, and the prefix match is
  the heuristic. The shared branch names no destination, so a location
  nothing there claims (`/metadata/:pid` today) lights nothing at all,
  which is the honest answer: Home would be a claim about where the
  visitor is that is not true.
- **An episode is pushed from its show, and its back button pops.**
  `/episodes/:pid` names no show, so `go` can build none beneath it. An
  earlier draft kept `go` and had the app bar walk *up* to the show
  instead, which left two back affordances doing different things - the
  button went to the show, the system gesture to Home - and left the up
  target null for as long as the detail was still loading. Pushing gives
  the screen one behaviour that both affordances share and a real page
  underneath. A link to an episode still resolves; leaving one opened that
  way lands on the podcasts hub, the nearest place its own location can
  name. Putting the show in the path (`/podcasts/:show/episodes/:pid`)
  would make `go` work with a real ancestry, and it is the podcasts
  phase's to decide, since half the call sites hold no show pid (an item
  detail carries none, which is why ADR-0021 has playback follow the
  episode to find it).
- Audiobooks is not a tab yet: there is no books hub to send anyone to,
  and the plan's own rule is that a domain tab hides when the server has
  nothing for it. Search and Downloads join on the same terms.
- On compact, the secondary destinations are still reached from the
  screens' own app bars. The sidebar lists them and the rail reaches them
  through one overflow menu, but a phone has room for the domains and
  nothing else, so the avatar menu the layout system calls for is the
  flip commit's to build when the old row goes away.
- The sidebar's collapsed state is in memory. It is a per-device client
  setting and the store that persists those rides the settings phase.
  *Since built: it persists, on native and in the browser both. See
  ADR-0027.*
- **`@staticIconProvider` came off `WaxIcons`** (amending ADR-0016). The
  annotation tells the release build's icon tree-shaker to ignore the
  constants declared in the annotated class, so a glyph ships only where
  the shaker finds its constant materialized at a use site it walks - and
  a reference from another package's widget code is not one. The sidebar
  is the first surface to name glyphs the design system's own components
  never use, and 32 of the 57 arrived as blank boxes in the release build
  while rendering correctly in every debug run, golden, and widget test.
  Removing the annotation ships the vendored subsets whole: 15 KB more,
  and MaterialIcons still shakes 1.6 MB down to 21 KB, which is where
  that optimization was ever worth anything. `icons_test.dart` fails if
  the annotation returns, because no rendering test can see this.
- **There is no skip-to-content link, and it cannot live in the shell.**
  9.2 asks for one, and the frame had one until it was proved dead: the
  branch navigator's route owns focus from the first frame and Flutter's
  traversal never leaves the scope it starts in, so a link rendered beside
  the content - in the outer route's scope - is unreachable by Tab, and it
  is absent from the semantics tree besides (it takes no room until
  focused, and a zero-size node is dropped). A working one has to sit in
  the scope that holds focus, which means the page scaffold rather than
  the shell, or a traversal group spanning both. Shipping an a11y control
  nobody can reach is worse than not shipping it, so it comes out and the
  requirement rides P8's accessibility pass with the manual screen-reader
  run.
- The shipped fonts were verified by reading the built subsets' `cmap`
  against the names `WaxIcons` declares, and the shell itself by driving
  the flag-on wasm build in a real browser at all three widths. Neither
  the goldens nor the widget tests could have caught either of the two
  release-shaped defects this phase turned up.
- Two rules here are only as good as the tests that visit the right state.
  Back interception passed a test that had only ever seen a branch root,
  and the `go`/`push` split passed tests that never stood in a stack worth
  losing. Both now have a case that fails without the fix: a branch
  drilled into and stepped out of, and a facet bucket that has to survive
  a book being opened from it.
