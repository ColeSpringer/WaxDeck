# skwasm renderer-race reproduction

Reproduction harness for flutter/flutter#190039: multi-threaded skwasm
corrupts its shared heap under concurrent paragraph layout and glyph
rasterization, then the page spins at 100% CPU forever. This is what
the e2e suite's old 1-in-4 "renderer hang" flake was, and why the app
ships skwasm single-threaded for now (`app/app/web/index.html`).

The harness stays because it answers, in seconds, the question the
suite would take dozens of runs to answer: is an engine still affected?
When a Flutter upgrade lands or the issue closes, run it before
removing the single-threaded force. This app's own index.html is the
stock template, so unlike the product it runs multi-threaded by
default, which is the point.

```sh
flutter build web --wasm          # in this directory
node serve.js &                   # :4499, with COOP/COEP like waxdeck serves
node drive.js                     # affected engine: traps within seconds
ST=1 node drive.js                # clean control: single-threaded, no fault
```

An affected engine traps with a wasm RuntimeError or silently stalls
within seconds to a minute; `drive.js` then dumps every chromium
thread twice (state, wait channel, CPU delta) into `evidence-*/`,
showing the UI thread and the render worker both spinning. A fixed
engine should match the ST control: steady rafCounts until the time
cap. Give a clean run at least 10 minutes before trusting it, and
re-test the suite with `WAXDECK_E2E_MT_SKWASM=1` for a few runs before
flipping the product config back.

Knobs: `node drive.js 'http://127.0.0.1:4499/?paragraphs=24&spans=6' 2 10`
runs 2 pages for up to 10 minutes at half the text pressure;
`?images=1` adds a strip of half-404 network images (not needed to
trap, kept because the production trace had a failed cover-art burst
at hang onset).
