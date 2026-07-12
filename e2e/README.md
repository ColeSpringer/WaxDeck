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

The compose-based harness comes later, alongside real library scanning and
real auth. It runs the full `waxdeck` + `waxflow` + `dex` (OIDC) stack from
`deploy/compose.yaml` under test instead of a bare binary.
