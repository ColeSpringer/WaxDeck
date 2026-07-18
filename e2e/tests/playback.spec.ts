import { test, expect, APIRequestContext } from '@playwright/test';
import { authed, ensureAdmin, waitForLibrary } from './helpers';

// Playback end to end over the real stack: the server scans a synthesized
// fixture library at startup and streams through the WaxFlow sidecar.
// These tests drive the API surface the clients use; the web-UI journey
// lives in ui.spec.ts.

async function loginToken(request: APIRequestContext): Promise<string> {
  return ensureAdmin(request);
}

test('scanned library browses, searches, and pages', async ({ request }) => {
  const token = await loginToken(request);
  await waitForLibrary(request, token);

  const items = await (
    await request.get('/api/v1/library/items', authed(token))
  ).json();
  const titles = items.items.map((it: { title: string }) => it.title);
  expect(titles).toContain('Alpha Song');
  expect(titles).toContain('Delta Song');

  const search = await (
    await request.get('/api/v1/library/search?q=Charlie', authed(token))
  ).json();
  expect(search.tracks.length).toBe(1);
  expect(search.tracks[0].title).toBe('Charlie Song');
});

for (const [title, file] of [
  ['Alpha Song', 'flac'],
  ['Bravo Song', 'mp3'],
  ['Charlie Song', 'opus'],
  ['Delta Song', 'vorbis'],
] as const) {
  test(`streams the ${file} fixture (${title})`, async ({ request }) => {
    const token = await loginToken(request);
    await waitForLibrary(request, token);

    const search = await (
      await request.get(
        `/api/v1/library/search?q=${encodeURIComponent(title)}`,
        authed(token),
      )
    ).json();
    expect(search.tracks.length).toBe(1);
    const pid = search.tracks[0].pid as string;

    const playInfo = await (
      await request.get(`/api/v1/items/${pid}/play-info`, authed(token))
    ).json();
    expect(playInfo.url).toContain('/media/stream?pid=');

    // The stream URL is media-token authenticated: playable with no
    // headers at all, the way audio elements and cast devices fetch it.
    const stream = await request.get(playInfo.url);
    expect(stream.status()).toBe(200);
    expect((await stream.body()).byteLength).toBeGreaterThan(1000);
  });
}

test('resume position and listen dedupe survive a replay', async ({ request }) => {
  const token = await loginToken(request);
  await waitForLibrary(request, token);

  const search = await (
    await request.get('/api/v1/library/search?q=Alpha', authed(token))
  ).json();
  const pid = search.tracks[0].pid as string;

  // Checkpoint a resume position and read it back, as a killed and
  // relaunched client would.
  const put = await request.put(`/api/v1/items/${pid}/play-state`, {
    ...authed(token),
    data: { positionMs: 421 },
  });
  expect(put.status()).toBe(204);
  const state = await (
    await request.get(`/api/v1/items/${pid}/play-state`, authed(token))
  ).json();
  expect(state.positionMs).toBe(421);

  // A duplicated listen report never double-counts. The ID is fresh per
  // attempt so CI retries do not collide with an earlier attempt's ingest.
  const report = {
    sessions: [
      {
        sessionId: `e2e-alpha-${Date.now()}-${test.info().workerIndex}`,
        pid,
        startedAt: new Date().toISOString(),
        msPlayed: 900,
        finished: true,
      },
    ],
  };
  const first = await (
    await request.post('/api/v1/listens', { ...authed(token), data: report })
  ).json();
  const second = await (
    await request.post('/api/v1/listens', { ...authed(token), data: report })
  ).json();
  expect(first.accepted + second.accepted).toBe(1);
  expect(second.duplicates).toBe(1);
});
