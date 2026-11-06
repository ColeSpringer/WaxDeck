# App translation fragments

The app's translation table, one directory per key prefix, one ARB file
per locale:

    player/en.arb    player/es.arb

`make generate` merges the fragments into
`lib/src/l10n/arb/app_<locale>.arb` - committed and drift-checked, like
the OpenAPI bundle - and runs gen-l10n over the result, so the build
never reads this tree directly and the merged files are never edited by
hand.

A key files under the longest directory name that prefixes it:
`playerSleepTimer` lives in `player/`, `booksTitle` lives in `book/` -
a list screen's keys shelve with their medium - and a prefix no
directory claims is a new directory.
`tools/gen-l10n-bundle.dart` enforces the rule, along with
duplicate keys and locale coverage; `test/l10n_arb_test.dart` checks
the content per fragment - descriptions, typed placeholders, sorted
keys, en/es parity - and that the committed bundles are exactly the
merge.

Adding a string: put the key and its `@key` metadata in the feature's
`en.arb`, the translation in the same directory's `es.arb`, keep both
sorted, and run `make generate`.

## The reading side

- Copy is a key read at the leaf: `context.l10n`, `context.waxL10n`.
  BuildContext never crosses into a provider - a controller answers a
  code or a token and the widget words it, which is also why a stored
  value is never a translation.
- What is drawn outside the element tree (the tray menu, Android Auto,
  the media session, download notifications) reads
  `offTreeL10nProvider`, which resolves the locale as the tree does.
- Errors go through `explainError` (the code picks the sentence, an
  unknown code falls back to the server's). A refusal of something the
  user just typed keeps the server's words via `explainRefusal`: it
  names the value and the table cannot.
- Dates, bytes, relatives and speeds through `WaxFormats`; durations in
  words through `WaxLocalizations`.
- es lands with en in the same change (`test/l10n_arb_test.dart` fails
  otherwise), machine-drafted until a native reader removes
  `@@x-machine-translated`.
- The `hardcoded-copy` ratchet in `test/ui_conventions_test.dart` only
  goes down. It reads copy by argument name, a few positional shapes and
  any interpolated literal holding prose (logs, exceptions, `toString`,
  header values and SQL aside), so zero is a claim to check by reading,
  and a floor above zero carries its reason at the site.
- e2e and the goldens read English by construction (pinned browser
  locale, blocked-out text), so a translation cannot red them and they
  do not gate one. Spanish draws in `test/settings_screen_test.dart`.

A fragment carries `@@locale` and may carry `@@x-` notes. The merge
carries notes through - the one the es fragments all share says the
Spanish copy was machine-drafted alongside extraction and needs native
review before Weblate onboarding - with one exception: `@@x-template`,
which every fragment sets to `en.arb`. That one is for VS Code's ARB
Editor extension, which would otherwise check each fragment against
l10n.yaml's whole-app template and report it missing the rest of the
table; pointed at the directory's own template it checks es.arb against
the sibling en.arb, live, the same parity `test/l10n_arb_test.dart`
enforces at test time. It describes the fragment file, not the locale,
so the merge drops it.

## The house rule

Explanatory text is the last resort; a layout, an icon or a label
usually says it. The rule the app is written to:

- An empty state is a title, at most one action and at most one line of
  8 words (`EmptyState.message`, optional, dropped when the title or the
  action already says it).
- A setting gets help only for a consequence its label hides, in at
  most 10 words.
- A format or example hint lives in the field's hint, not under it. A
  hint fits the lines its field shows on a phone, in every language
  (one, in a one-line field), and goes at the first keystroke, so it
  holds a format or an example and nothing else; what a blank box means
  is help under the field.
- An overline is at most three words and never restates the heading
  below it; no blurb sits under a heading.
- A paragraph belongs only in a first-run step or in a confirmation
  that deletes, overwrites or sends data off the machine: at most 25
  words, saying what is lost.
- A tally or provenance line appears only where no per-item mark
  exists; otherwise it sits behind a `WaxInfoTip`. Rows and headers hold
  one in their own slot (`WaxSettingRow.info`, `SectionHeader.info`, a
  button's `WaxButton.detail`); a free `WaxInfoTip` never sits under an
  ancestor that merges or excludes semantics, where a tap on the web
  goes to that ancestor and the tip never opens (`hasOwnSemanticsNode`
  in the tests checks it).
- A scope or state flag is an icon with an accessible name.
- Errors, refusals and notification bodies are exempt, but say the
  cause and the next step.

## The prose budget

`test/l10n_arb_test.dart` measures the en copy by key suffix, in the
longest variant of a plural or select (a placeholder is one word):

| Suffix         | Cap |
| -------------- | --- |
| `EmptyMessage` | 8   |
| `Message`      | 8   |
| `Help`         | 10  |
| `Overline`     | 3   |
| `Blurb`        | 0   |
| `Body`         | 25  |

The first suffix a key ends with is its class, so an empty state's
line is an `EmptyMessage` before it is a `Message`. A key with none of
these suffixes is not measured. Exempt: every key
under `error/`, keys ending `Error`, `Refused`, `Invalid` or
`Keywords`, and any notification body the test names (none today: the
`notif*Help` keys double as inbox bodies and are measured as `Help`).

Name a key by where its words draw, so the budget reads it: a key
ending `Hint` draws inside a field (not measured: a format or an
example, and `test/field_hints_test.dart` checks the settings dialogs'
hints fit a phone in en and es), one ending `Help` under a control,
behind an info tip or as a button's detail, one ending `EmptyMessage`
under an empty state's title, one ending `Message` on a banner, a
refusal page or a short dialog, and one ending `Body` in a confirmation.
The test holds the slots to it: a key passed to `EmptyState(message:)`
that does not end `EmptyMessage` fails, and so does one passed to an
`info:` slot, `WaxInfoTip(message:)` or `WaxButton(detail:)` that does
not end `Help` (errors are exempt). A class word inside a key ends it:
`adminGenreParentHasChildrenHelp`, never
`adminGenreParentHelpHasChildren`, which the test fails as a line that
would otherwise escape its cap.

A key over its cap is listed in `test/prose_budget.json` with its
current word count as a ceiling, which only falls: more words fails, and
fewer fails until the entry is lowered or, once the key fits its cap,
removed. A key with no entry gets its cap and no tolerance, so a new
blurb fails outright. After adding a class, re-seed with
`WAXDECK_PROSE_BUDGET=write flutter test test/l10n_arb_test.dart`.
