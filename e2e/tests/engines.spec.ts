import { test, expect } from './fixtures';

// Which build each engine is handed. index.html opts Firefox into the
// wasm build beside Chromium and keeps Safari on the JavaScript one on
// purpose (docs/deferred-work.md). Where dart2wasm cannot run, the
// loader quietly hands over the JavaScript build instead: the app still
// works, so nothing but this would say that it had.
test('each engine runs the build it is meant to', async ({ app, page, browserName }) => {
  await app.nav.enter('home');
  await expect(app.home.shelf('recent')).toBeVisible();

  const loaded = await page.evaluate(() =>
    performance.getEntriesByType('resource').map((entry) => new URL(entry.name).pathname),
  );
  // Content-hashed or not: main.dart.wasm or main.dart.1a2b3c4d.wasm.
  const entrypoint = (ext: string) =>
    loaded.filter((p) => new RegExp(`/main\\.dart(\\.[0-9a-f]{8})?\\.${ext}$`).test(p));

  if (browserName === 'webkit') {
    expect(entrypoint('js'), 'Safari runs the JavaScript build').toHaveLength(1);
    expect(entrypoint('wasm'), 'and not the wasm one').toEqual([]);
    return;
  }

  // skwasm needs WebGL, and without it the loader picks the JavaScript
  // build however capable the engine: a failure here is the machine.
  const webgl = await page.evaluate(
    () => document.createElement('canvas').getContext('webgl2') !== null,
  );
  expect(
    webgl,
    'the page has WebGL2 (headless Firefox gets none without a GPU: WAXDECK_E2E_FIREFOX_HEADED under xvfb-run)',
  ).toBe(true);
  expect(entrypoint('wasm'), 'the wasm entrypoint is loaded').toHaveLength(1);
  expect(entrypoint('js'), 'the JavaScript build is not').toEqual([]);
  expect(
    loaded.filter((p) => /\/canvaskit\/skwasm(_heavy)?\.wasm$/.test(p)),
    'skwasm is the renderer',
  ).toHaveLength(1);
});
