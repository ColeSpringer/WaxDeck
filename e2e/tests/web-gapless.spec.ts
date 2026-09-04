import { test, expect } from './fixtures';
import { T } from './driver';
import { SemanticsIds } from './semantics-ids';
import type { components } from './api-types';

type TimelineFormat = components['schemas']['TimelineFormat'];

// Gapless playback in a browser, over the real stack: the switch, the
// mint it causes, the HLS tree serving it, and a queue crossing from
// one track to the next inside one stream.
//
// The whole point of the arrangement is that the crossing is not a
// load, so what this asserts is that the deck walks from one track to
// the next while exactly one timeline was minted and one master was
// fetched - a per-item path would have minted none and opened a stream
// URL per track instead.

test('a music queue plays as one stream and crosses inside it', async ({ app, page }) => {
  // Whether this server renders timelines at all. Without a streaming
  // engine there is nothing to switch on, and the switch says so on
  // screen rather than pretending.
  const { pid } = await app.seed.item('Alpha Song');
  const probe = await app.api.raw.post('/player/timeline', {
    data: { itemPids: [pid] },
  });
  test.skip(probe.status() === 501, 'this stack renders no queue timelines');

  // Every mint this page made, with what the server answered. The
  // status matters: a 202 is the server still measuring the members,
  // which the feeder answers by asking again a few seconds later, so a
  // cold engine produces two POSTs for one rendering. That is the
  // designed path and must not read as a mint per track.
  const mints: {
    formats?: TimelineFormat[];
    itemPids?: string[];
    status?: number;
  }[] = [];
  // Browser-side diagnostics: a stream lost mid-listen re-mints, and
  // what said so is in the console.
  const noise: string[] = [];
  page.on('console', (message) => {
    const text = message.text();
    // The app's own debugPrint reaches the console in a release web
    // build, and it is where every give-up on this path says so.
    if (/timeline|preload/i.test(text)) noise.push(text.slice(0, 200));
    else if (message.type() === 'error' && !/art\?size|woff2|Failed to load resource/.test(text)) {
      noise.push(text.slice(0, 120));
    }
  });
  page.on('pageerror', (error) => noise.push(`pageerror: ${error.message.slice(0, 160)}`));
  page.on('response', (response) => {
    if (response.status() >= 400) {
      noise.push(`http ${response.status()} ${response.url().slice(0, 120)}`);
    }
  });
  const master: string[] = [];
  const segments: string[] = [];
  const streams: string[] = [];

  page.on('response', (response) => {
    const request = response.request();
    if (request.method() === 'POST' && response.url().includes('/player/timeline')) {
      mints.push({
        ...JSON.parse(request.postData() ?? '{}'),
        status: response.status(),
      });
    }
  });

  page.on('request', (request) => {
    const url = request.url();
    if (url.includes('/media/hls/master.m3u8?tl=')) master.push(url);
    else if (url.includes('/media/hls/')) segments.push(url);
    else if (url.includes('/media/stream?')) streams.push(url);
  });

  // Reached the way a listener reaches it, which also lands the row on
  // screen: the section is longer than the window and a row below the
  // fold has no rect to click.
  await app.nav.enter('settings');
  await app.settings.findAndOpen('gapless', 'web-gapless', 'web-gapless');
  await app.settings.setting('web-gapless').click();
  // Per device, so it lands in this browser's own storage and the
  // account's document never hears about it.
  await expect(app.settings.setting('web-gapless')).toBeChecked();

  // One album rather than the whole tracks index: a rendering covers a
  // run of music, and the index is everything the library holds -
  // including sources the engine will not put in one stream, which is
  // a refusal rather than a gapless queue.
  await app.nav.enter('albums');
  await app.music.openEntity(0);
  await app.music.playEntity('play');

  // One mint for the whole run, carrying what this browser can actually
  // decode. Never aac first: Playwright's Chromium ships without the
  // proprietary codecs, so a server that rendered aac would hand it
  // silence with nothing to explain it.
  await expect
    .poll(() => mints.length, { timeout: T.fetch, message: 'the queue should mint one timeline' })
    .toBeGreaterThan(0);
  expect(mints[0].formats?.[0]).not.toBe('aac');
  const crossing = (mints[0].itemPids ?? []).slice(0, 2);
  expect(crossing.length, 'the run should hold more than one track').toBe(2);

  // The answer says what it actually rendered, and it is one of the
  // formats that were asked for rather than the server's own ladder.
  const minted = await app.api.raw.post('/player/timeline', {
    data: { itemPids: crossing, formats: mints[0].formats },
  });
  expect(minted.status()).toBe(201);
  expect(mints[0].formats).toContain((await minted.json()).format);

  // The proxied HLS tree is what actually plays: the master under the
  // media token this server minted, then the segments its playlists
  // name.
  await expect
    .poll(() => master.length, { timeout: T.fetch, message: 'the master playlist should be fetched' })
    .toBeGreaterThan(0);
  await expect
    .poll(() => segments.length, { timeout: T.fetch, message: 'segments should be fetched' })
    .toBeGreaterThan(0);

  // The crossing, seen where a listener sees it: the deck names the
  // first member, then the second, with nothing loaded in between.
  const titles = await Promise.all(
    crossing.map(async (item) =>
      (await app.api.get('/items/{pid}', { path: { pid: item } })).title,
    ),
  );
  await expect(app.player.text(titles[0])).toBeVisible({ timeout: T.nav });
  await expect(app.player.text(titles[1])).toBeVisible({ timeout: T.fetch });

  // And still one rendering: the crossing happened inside the stream
  // that was already loaded.
  //
  // Counted by the mints that produced one, not by POSTs, because a
  // server still measuring answers 202 and is asked again - two
  // requests, one rendering. Anything else answered is a failure of its
  // own and reds here rather than being counted as a rendering.
  //
  // The message carries what was asked for and what was fetched,
  // because a second rendering means one of several different things -
  // a run that stopped early, a stream that was lost, a queue the engine
  // refused - and a failure in CI has no other way to say which.
  const trace =
    `${mints
      .map((m) => `${m.status}:${(m.itemPids ?? []).length}`)
      .join(', ')}; ${master.length} masters, ${segments.length} segments, ` +
    `${streams.length} per-item streams; console ` +
    JSON.stringify(noise.slice(0, 12));
  expect(
    mints.filter((m) => m.status === 201).length,
    `one rendering for the run; got ${trace}`,
  ).toBe(1);
  expect(
    mints.filter((m) => m.status !== 201 && m.status !== 202),
    `every mint should be a rendering or a measurement; got ${trace}`,
  ).toEqual([]);
});

test('the switch is a browser-only row, found the way any other is', async ({ app }) => {
  await app.nav.enter('settings');

  // Registered, drawn, and reachable by search the way every other
  // setting is - the half a widget test on the VM cannot check, because
  // the row is gated on running in a browser.
  await app.settings.findAndOpen('gapless', 'web-gapless', 'web-gapless');
  expect(app.nav.location()).toMatch(/settings\/playback/);
  await expect(app.settings.setting('web-gapless')).toBeVisible();
  expect(SemanticsIds.setting('web-gapless')).toBe('setting-web-gapless');
});
