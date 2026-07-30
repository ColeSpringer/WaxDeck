# WaxDeck e2e

Playwright smoke tests against a real server binary with the embedded web UI.

## Running locally

```sh
make e2e         # rebuilds the UI and the binary if stale, then runs
```

`make e2e` brings the thing under test up to date itself: the Flutter web
build when a Dart source is newer than the embedded bundle, and the server
binary always, since it embeds that bundle at link time. It used to be on
the caller to run `make web build` first, and forgetting meant the suite
drove the *previous* build — which reads exactly like a missing feature
and fails on whichever spec touched it rather than saying the bundle is
stale.

The Flutter compile is guarded by a real-file stamp against the Dart
sources, so a spec-only or Go-only iteration does not pay for one. Note
that `make generate` rewrites generated Dart, so the first `make e2e`
after it rebuilds the bundle.

The config's `webServer` starts `server/waxdeck` and waits on
`/api/v1/health`; set `WAXDECK_BASE_URL` to target an already-running
instance instead (`reuseExistingServer` is on). With that set, `make e2e`
rebuilds nothing: the stack is the caller's, not ours.

## How this harness grows

New scenarios are added over time, each exercising a walking-skeleton slice
end to end (currently: serve the UI and answer health; later: browse a
scanned library, and so on). Keep specs small and additive: this suite is the
contract that "the whole thing still boots and plays".

The stack includes a small test identity provider (`fixtures/cmd/testidp`)
so the single sign-on journey runs against a real HTTP IdP: discovery,
JWKS, an interactive login form, PKCE, and single-use codes. The
compose-based harness comes later; it swaps the bare binaries for the
full `waxdeck` + `waxflow` stack from `deploy/compose.yaml` with `dex`
as the identity provider.

Specs run against the full Chromium in its new headless mode
(`channel: 'chromium'`), not the `chrome-headless-shell` Playwright
reaches for by default. The web build is wasm, and skwasm rasterizes in
a dedicated worker behind SharedArrayBuffer; the shell segfaults on
that under load, which arrives as an unexplained "Page crashed" in
whichever spec was mid-login. `npx playwright install chromium`
provides both binaries, so nothing changes about setup.

The first spec to run is the first-run setup wizard (the `setup`
Playwright project); every other spec depends on it and reaches the
shared administrator through `tests/helpers.ts`, which bootstraps or
logs in as needed. Against a reused dev stack the wizard spec skips
itself (the one-shot door is already closed).
