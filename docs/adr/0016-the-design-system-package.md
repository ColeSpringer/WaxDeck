# 16. The design system is a package, and it owns its type and icons

Date: 2026-07-25

## Status

Accepted.

## Context

The client rewrite needs a design system: tokens, themes, and the
components every screen composes. Three questions had to be settled
before the first component could be written, and each has a wrong answer
that is expensive to reverse once forty screens depend on it.

**Where the design system lives.** Components in `app/app` alongside the
screens would let a component reach for `waxdeck_api` models "just this
once", and golden tests would then need the API fakes to render a card.

**Where the type comes from.** Flutter web resolves glyphs its bundled
fonts lack by fetching Noto from Google's CDN at runtime. WaxDeck is
self-hosted and frequently LAN-only, so on those instances Arabic,
Hebrew, Thai, and CJK metadata would render as boxes with no failure
anyone could diagnose from the app.

**Where the icons come from.** `phosphor_flutter` is the natural
dependency for the icon set, and it cannot compile against Flutter 3.44:
it subclasses `IconData`, which is now a `final class`.

## Decision

**`app/packages/waxdeck_ui` is a Flutter-only package.** It depends on
Flutter and nothing else in the workspace, and it never imports
`waxdeck_api`. Components take plain view-data structs
(`MediaTileData`, `NowPlayingData`); screens map API models at the call
site. The package re-exports `package:flutter/material.dart`, and the
house rule for new client code is to import
`package:waxdeck_ui/waxdeck_ui.dart` only, so the eventual move of
Material into the `material_ui` package is one export line rather than a
sweep across every screen.

**Type is bundled, subset, and owned.** Archivo (display), Inter (UI),
and Spline Sans Mono (readouts) ship as variable fonts, about 1.3 MB of
eager chain produced by `tools/fetch-fonts.sh` from pinned upstream
revisions. The type tokens select weights through `FontVariation`,
because the scale uses 460, 520, 560, 620, and 640 and Archivo's width
axis, none of which `FontWeight`'s 100-step ladder can reach. The
fallback scripts are all deferred: Noto Sans Arabic, Hebrew, and Thai
subsets (750 KB together) plus the full Noto Sans CJK SC face (16 MB,
deliberately unsubset so no name outside a curated core can render as
boxes) live in `assets/fonts/`, and `WaxFonts.ensureFor(text)` loads
each from WaxDeck's own origin the first time on-screen text needs its
script, degrading to the platform's own fallback when an asset is
absent. The full face costs one 16 MB fetch on the first CJK library
and nothing on an all-Latin one, which is the right side of that trade
for a self-hosted server; text that raced ahead of its face re-lays out
when the loader lands.

The web engine has two font paths of its own that ignore all of the
above, and both are closed deliberately. Its hard-coded default family
is Roboto, downloaded from Google's CDN regardless of what the theme
names, so `web/index.html` sets `fontFallbackBaseUrl` to an unrouted
same-origin path (the server reserves the SPA shell for document
navigations and answers every subresource miss with an honest 404, so
the engine's probes fail cleanly wherever they land). No bundled
Roboto stands in for the default: the engine's check wants a family
literally named Roboto, a package declaration registers under a
`packages/waxdeck_ui/` prefix it never matches, and an app-level one
would ship a duplicate face just to satisfy a name. The engine's one
default-font probe 404s on this origin instead, and the theme's
family plus fallback chain is what every style actually resolves
through. The same redirect neutralizes the engine's per-glyph Noto
shard downloads, which would otherwise race the deferred loader to the
CDN the first time a non-Latin name appears. The consequence is owned:
scripts outside the bundled set render tofu on web whether or not the
instance can reach the internet, identically, and growing coverage
means adding a face to `tools/fetch-fonts.sh`, not hoping a CDN is
reachable. `e2e/tests/fonts.spec.ts` asserts the whole journey stays
on-origin.

**Icons are vendored as two subset fonts.** Phosphor (MIT) regular and
fill are subset by `tools/fetch-icons.sh` to exactly the codepoints
`WaxIcons` names: 27 KB for both weights against the 950 KB the upstream
pair would cost. `WaxIcon` wraps them, so call sites name a glyph and a
state rather than a font family, and `test/icons_test.dart` fails if a
named glyph is missing from the shipped subsets. (Amended by ADR-0022:
`WaxIcons` carried `@staticIconProvider`, which hid its constants from
the release build's icon tree-shaker and shipped 32 of the 57 as blank
boxes. The annotation is gone and a source check keeps it gone; the
subsets were already the curation it was trying to perform.)

**The design system emits no semantics identifiers.** Identifiers are a
contract between the app and the e2e suite, generated into both from
`app/semantics-ids.json` (CLAUDE.md rule 8), and `waxdeck_ui` cannot see
that registry. So components take their handles from the caller: single
controls through a `semanticsId` argument, composite surfaces through a
slot type (`DeckBarIds`, `PlayerIds`) the shell fills from `SemanticsIds`.
A component that invented its own would put a second definition of the
same contract string in a package no drift check watches.

## Consequences

Golden tests render the design system without any API fake in scope, and
a component cannot quietly acquire an API dependency: the import would
not resolve.

The contrast pair matrix (`test/contrast_test.dart`) enumerates every
foreground/surface pairing the tokens land on and fails the build when
one drops below WCAG AA. Writing it found six pairings in the drafted
palette that did not hold, including hint text on dialogs and the
component border the design language claimed was 3:1 on every surface.
Those tokens were corrected; the matrix is what keeps them corrected.

Fonts and icons are regenerated by scripts rather than by hand, which
makes the upstream revision, the subset ranges, and the glyph list
reviewable in a diff. Both scripts provision their own tooling
(`tools/.cache`), so neither depends on what happens to be installed.

The vendored icons cost a step: adding an icon means naming it in
`wax_icon.dart` and re-running `tools/fetch-icons.sh`. The test that
compares the two makes forgetting it a failure rather than a blank box
at runtime. If `phosphor_flutter` becomes compatible again, adopting it
is a change inside `WaxIcon`, which is the reason for the wrapper.

Handles arriving from the caller costs a slot type per composite surface
and means a component rendered without one has no e2e handle at all. That
is the right failure: a missing handle is a spec that cannot find its
control, which is loud, where a duplicated identifier is a contract that
quietly means two things.
