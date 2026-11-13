# waxdeck_ui

WaxDeck's design system: the tokens, themes, and components every client
screen composes. Flutter only, by rule - this package never
imports `waxdeck_api`, so components take plain view-data structs and the
app maps API models at the call site.

## Using it

```dart
import 'package:waxdeck_ui/waxdeck_ui.dart';
```

That one import covers Material too: the library re-exports
`package:material_ui/material_ui.dart`, pinned here and nowhere else.
Never import the SDK's `package:flutter/material.dart` beside it: its
widgets are other types, and find no theme or Material above them.

```dart
MaterialApp(
  theme: buildWaxTheme(variant: WaxThemeVariant.light),
  darkTheme: buildWaxTheme(variant: WaxThemeVariant.dark),   // or .oled
  localizationsDelegates: waxLocalizationsDelegates,
  // English first: resolution falls back to the first entry, and
  // gen-l10n's list is alphabetical.
  supportedLocales: [
    const Locale('en'),
    ...WaxLocalizations.supportedLocales.where((l) => l != const Locale('en')),
  ],
);

final colors = WaxColors.of(context);   // surfaces, text, accent, domain hues
final layout = WaxLayout.of(context);   // density-aware metrics
final motion = WaxMotion.of(context);   // reduced-motion aware durations
```

## The catalogue

```sh
cd example && flutter pub get && flutter run -d chrome
```

Every component in all three themes, at both densities and two text
scales, plus the full-screen composites (home, album detail, the four
player faces, the deck bar in each medium). The catalogue is the review
surface: a component is not finished until it has been seen here with
real strings in it, in light as well as dark.

## What is generated

Nothing here is hand-drawn or hand-copied:

| Command | Produces |
|---|---|
| `make fonts` | `fonts/*-Variable.ttf`: Archivo, Inter, Spline Sans Mono; in `assets/fonts/` the Noto fallbacks (a variable face per script, `NotoSansCJK.otf`, `NotoColorEmoji.ttf`); their licenses in `fonts/licenses/`; and in `app/app/web/vendor/wax-font-fallback/` the web engine's default face with its license. Each face is pinned to an upstream revision or checksum, and subset except the CJK face and the web engine's |
| `make icons` | `fonts/Phosphor*-Subset.ttf`: the two icon weights, subset to the codepoints `WaxIcons` names |
| `make brand` | the mark, the app icons for every platform, the wordmark SVG, and the player backdrop's grain |

Adding an icon means naming it in `lib/src/icons/wax_icon.dart` and
re-running `make icons`; `test/icons_test.dart` fails if the two
disagree.

## Tests

- `contrast_test.dart` enumerates every foreground/surface pairing the
  tokens land on, in all three themes, and fails below WCAG AA. Fix the
  token, not the test.
- `typography_test.dart` proves the variable axes actually render: a
  dropped `fvar` table looks fine in a screenshot and measures
  identically at every weight, which is exactly how it would slip
  through review.
- `components_golden_test.dart` (here) and `composites_golden_test.dart`
  (in `example/`) hold the rendering. Both baseline two ways: CI goldens
  with text as blocks, identical on every host, and readable Linux
  goldens where the type is really the type.
- `semantics_merge_test.dart` audits every tap for a node of its own,
  since on web a click lands on the node and not the handler under it.
  It fails on any public component in `lib/src/components/` it has not
  classified: give a new one a scenario in that file, or add it to the
  test's non-interactive list if it handles no tap.

Regenerate the CI goldens with `flutter test --update-goldens` in this
package and in `example/`, on any host, and the readable ones with
`make goldens-linux` at the repo root, which renders them for this
package and `example/` in a container (Docker is the only
prerequisite). A design-system change wants both.
