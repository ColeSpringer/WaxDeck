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
  //
  // Found by the queue holding the track, not by any one position in
  // it. Playing a row in a listing queues the listing from there, so
  // entry zero is whatever the index happens to open with - and the
  // index itself moves, because this test never pauses and a fixture
  // track is a few seconds long, so a predicate reading the current
  // entry stops matching at the first boundary and reports a mirroring
  // failure that never happened.
  let sessionId = '';
  await expect
    .poll(
      async () => {
        const listed = await app.api.tryGet('/player/sessions');
        const found = (listed?.sessions ?? []).find((s) =>
          (s.entries ?? []).some((e) => e.pid === target.pid),
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

  // Client B: plays another item into its dock, expands its own
  // player, then opens the device picker and finds A's session listed.
  const b = await device();
  await b.nav.enter('tracks');
  await b.music.play(other.pid);
  await b.player.ready();
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

// The other direction: not "take that session over", but "send mine
// there". A device plays one thing, so casting from one that is playing
// is a handoff - the queue moves, the target starts, and the source goes
// quiet rather than playing the same album into the room it just left.
test('casting from a playing browser silences it and the bar follows', async ({
  app,
  device,
}) => {
  const mine = await app.seed.item('Alpha Song');
  const parked = await app.seed.item('Bravo Song');

  // B first: its endpoint id is read off the session it mirrors, which
  // is the only way to tell one browser's client endpoint from another's
  // on an account several of them are signed into.
  const b = await device();
  await b.nav.enter('tracks');
  await b.music.play(parked.pid);
  let bEndpoint = '';
  await expect
    .poll(
      async () => {
        const listed = await app.api.tryGet('/player/sessions');
        const found = (listed?.sessions ?? []).find((s) =>
          (s.entries ?? []).some((e) => e.pid === parked.pid),
        );
        if (found === undefined) return undefined;
        bEndpoint = found.endpointId;
        return found.authority;
      },
      { message: "B's session should mirror so its endpoint can be named" },
    )
    .toBe('mirror');

  // A plays its own track, then sends it to B.
  const a = await device();
  await a.nav.enter('tracks');
  await a.music.play(mine.pid);
  let aEndpoint = '';
  await expect
    .poll(async () => {
      const listed = await app.api.tryGet('/player/sessions');
      const found = (listed?.sessions ?? []).find((s) =>
        (s.entries ?? []).some((e) => e.pid === mine.pid),
      );
      if (found === undefined) return undefined;
      aEndpoint = found.endpointId;
      return found.authority;
    })
    .toBe('mirror');

  await a.cast.openPicker();
  await a.cast.playOn(bEndpoint);

  // A's bar changed face: the local one carries a queue panel and the
  // remote one, which drives another endpoint, does not.
  await expect(a.cast.localFace()).toBeHidden({ timeout: T.nav });

  // And the server agrees about where the sound is: A's track plays on
  // B's endpoint, and A holds nothing.
  await expect
    .poll(
      async () => {
        const listed = await app.api.tryGet('/player/sessions');
        const sessions = listed?.sessions ?? [];
        const there = sessions.find((s) => s.endpointId === bEndpoint);
        const here = sessions.find((s) => s.endpointId === aEndpoint);
        if (there === undefined) return 'nothing on B';
        if (here !== undefined) return 'A still holds a session';
        return (there.entries ?? []).some((e) => e.pid === mine.pid)
          ? 'handed over'
          : "B is playing something that is not A's";
      },
      { message: 'the queue should have moved, and the source let go' },
    )
    .toBe('handed over');
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
