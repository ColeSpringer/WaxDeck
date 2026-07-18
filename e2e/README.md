# WaxDeck e2e

Playwright smoke tests against a real server binary with the embedded web UI.

## Running locally

```sh
make web build   # build the Flutter web app and the server with -tags withweb
make e2e         # npm ci + playwright test (launches ../server/waxdeck itself)
```

The config's `webServer` starts `server/waxdeck` and waits on
`/api/v1/health`; set `WAXDECK_BASE_URL` to target an already-running
instance instead (`reuseExistingServer` is on).

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

The first spec to run is the first-run setup wizard (the `setup`
Playwright project); every other spec depends on it and reaches the
shared administrator through `tests/helpers.ts`, which bootstraps or
logs in as needed. Against a reused dev stack the wizard spec skips
itself (the one-shot door is already closed).
