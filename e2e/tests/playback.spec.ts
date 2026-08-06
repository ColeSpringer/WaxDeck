import { test, expect } from './fixtures';

// Playback end to end over the real stack: the server scans a synthesized
// fixture library at startup and streams through the WaxFlow sidecar.
// These tests drive the API surface the clients use; the web-UI journey
// lives in ui.spec.ts.

test('scanned library browses, searches, and pages', async ({ app }) => {
  const items = await app.api.get('/library/items');
  const titles = (items.items ?? []).map((it) => it.title);
  expect(titles).toContain('Alpha Song');
  expect(titles).toContain('Delta Song');

  const search = await app.api.get('/library/search', { query: { q: 'Charlie' } });
  expect(search.tracks?.length).toBe(1);
  expect(search.tracks?.[0]?.title).toBe('Charlie Song');
});

for (const [title, file] of [
  ['Alpha Song', 'flac'],
  ['Bravo Song', 'mp3'],
  ['Charlie Song', 'opus'],
  ['Delta Song', 'vorbis'],
] as const) {
  test(`streams the ${file} fixture (${title})`, async ({ app }) => {
    const { pid } = await app.seed.item(title);

    const playInfo = await app.api.get('/items/{pid}/play-info', { path: { pid } });
    expect(playInfo.url).toContain('/media/stream?pid=');

    // The stream URL is media-token authenticated: playable with no
    // headers at all, the way audio elements and cast devices fetch it.
    // `minted` rather than a typed path, because the server built this
    // one and its query is not a contract this suite can hold.
    const stream = await app.api.raw.minted(playInfo.url);
    expect(stream.status()).toBe(200);
    expect((await stream.body()).byteLength).toBeGreaterThan(1000);
  });
}

test('resume position and listen dedupe survive a replay', async ({ app }) => {
  const { pid } = await app.seed.item('Alpha Song');

  // Checkpoint a resume position and read it back, as a killed and
  // relaunched client would. Through `raw` for the status: 204 with no
  // body is what the contract says a checkpoint answers, and a server
  // that started returning the document instead would still satisfy the
  // read below.
  const put = await app.api.raw.put('/items/{pid}/play-state', {
    path: { pid },
    data: { positionMs: 421 },
  });
  expect(put.status()).toBe(204);
  const state = await app.api.get('/items/{pid}/play-state', { path: { pid } });
  expect(state.positionMs).toBe(421);

  // A duplicated listen report never double-counts. The ID is fresh per
  // attempt so a retry - which lands on this same account by design -
  // does not collide with the earlier attempt's ingest.
  const report = {
    sessions: [
      {
        sessionId: `e2e-alpha-${Date.now().toString(36)}`,
        pid,
        startedAt: new Date().toISOString(),
        msPlayed: 900,
        finished: true,
        // Required by the contract, and absent from the hand-typed body
        // this replaced: the server was defaulting it, so the suite has
        // been reporting listens the app itself would not send.
        source: 'live' as const,
      },
    ],
  };
  const first = await app.api.post('/listens', { data: report });
  const second = await app.api.post('/listens', { data: report });
  expect(first.accepted + second.accepted).toBe(1);
  expect(second.duplicates).toBe(1);
});
