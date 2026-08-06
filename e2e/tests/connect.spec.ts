import { test, expect } from './fixtures';
import { T } from './driver';

// Connect: every signed-in client is a controller and a controllable
// endpoint. Two live web clients, one listener: A plays locally and
// mirrors its session to the server; B sees the session, remote-controls
// it, and finally pulls the playback onto itself.
//
// Sessions are visible to their owner alone (or on a shared endpoint),
// so the two clients below see each other and nobody else. That used to
// need a fixed `connect-e2e` account written into this file, because the
// administrator every spec shared was playing several things at once and
// a session picked out of that list by the track it carries could easily
// be another spec's - which then ends when its browser closes.

test('a session mirrors to the server and relays remote control', async ({ app, device }) => {
  const target = await app.seed.item('Alpha Song');
  const other = await app.seed.item('Bravo Song');

  // Client A: plays the track on its own player.
  const a = await device();
  await a.nav.enter('tracks');
  await a.music.play(target.pid);

  // A's playback reaches the server as a mirror session, and this
  // account plays nothing else, so it is the only one listed.
  let sessionId = '';
  await expect
    .poll(
      async () => {
        const listed = await app.api.tryGet('/player/sessions');
        const found = (listed?.sessions ?? []).find(
          (s) => s.entries?.[0]?.pid === target.pid,
        );
        if (found === undefined) return undefined;
        sessionId = found.id;
        return found.authority;
      },
      { message: "A's session should mirror to the server" },
    )
    .toBe('mirror');

  // A's endpoint lists too.
  const endpoints = await app.api.get('/player/endpoints');
  expect((endpoints.endpoints ?? []).some((e) => e.kind === 'client')).toBe(true);

  // Client B: opens its own player screen on another item, then the
  // device picker, and finds A's session listed.
  const b = await device();
  await b.nav.enter('tracks');
  await b.music.play(other.pid);
  await b.cast.openFromPlayer();
  await b.cast.takeOver(sessionId);

  // The remote screen renders A's playback and pauses it; the pause
  // must land on A's real engine, observed through the session state
  // the server republishes.
  await b.cast.pressRemote();
  await expect
    .poll(async () => {
      const state = await app.api.tryGet('/player/sessions/{sessionId}', {
        path: { sessionId },
      });
      return state === undefined ? 'gone' : state.playing;
    })
    .toBe(false);
});

// The gapless transcode path against the real engine: the timeline
// mints over the API and its proxied HLS playlist serves, boundaries
// mapping both queue members onto one continuous presentation.
test('a queue timeline mints and serves through the real engine', async ({ app, request }) => {
  const pids = [
    (await app.seed.item('Alpha Song')).pid,
    (await app.seed.item('Bravo Song')).pid,
  ];

  const tl = await app.api.post('/player/timeline', { data: { itemPids: pids } });
  expect(tl.mimeType).toBe('application/vnd.apple.mpegurl');
  expect(tl.boundaries.length).toBe(2);
  expect(tl.boundaries[0].pid).toBe(pids[0]);
  expect(tl.boundaries[1].offsetSamples).toBeGreaterThan(0);

  // The playlist URL is one the server minted and carries its own
  // token, so it is fetched the way a player fetches it.
  const master = await request.get(tl.url, { timeout: T.fetch });
  expect(master.status()).toBe(200);
  const body = await master.text();
  expect(body).toContain('#EXTM3U');
  expect(body).toContain('mt=');
});
