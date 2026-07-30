# waxdeck_ui

WaxDeck's design system: the tokens, themes, and components every client
screen composes. Flutter only, by rule (ADR-0016) - this package never
imports `waxdeck_api`, so components take plain view-data structs and the
app maps API models at the call site.

## Using it

```dart
import 'package:waxdeck_ui/waxdeck_ui.dart';
```

That one import covers Material too: the library re-exports
`package:flutter/material.dart`, which is what makes the eventual move to
the `material_ui` package a change here instead of a sweep across every
screen.

```dart
MaterialApp(
  theme: buildWaxTheme(variant: WaxThemeVariant.light),
  darkTheme: buildWaxTheme(variant: WaxThemeVariant.dark),   // or .oled
);

final colors = WaxColors.of(context);   // surfaces, text, accent, domain hues
final layout = WaxLayout.of(context);   // density-aware metrics
final motion = WaxMotion.of(context);   // reduced-motion aware durations
```

## The catalogue

```sh
cd example && flutter run -d chrome
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
| `make fonts` | `fonts/*-Variable.ttf`: Archivo, Inter, Spline Sans Mono, and the Noto fallbacks, subset from a pinned upstream revision |
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

Regenerate goldens with `flutter test --update-goldens` in this package
and in `example/`.
