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
  goes down. It cannot see copy outside the element tree or in
  positional arguments, so zero is a claim to check by reading; what it
  cannot reach is in `docs/deferred-work.md`, and a floor above zero
  carries its reason at the site.
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
