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
