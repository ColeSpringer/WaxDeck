import { test, expect } from './fixtures';
import { J, T } from './driver';

// The discovery slice over the real stack: an instant mix started from
// a playing track in the browser, the sonic surfaces (similar tracks
// and paths) once the embedded analyzer has swept the fixture library,
// the worker API's token gate, and the streaming-service playlist
// import round trip with its portable export.

// Matches the token run-stack.sh hands the server.
const WORKER_TOKEN = 'e2e-worker-token';

test('an instant mix starts from any playing track', async ({ app }) => {
  const { pid } = await app.seed.item('Bravo Song');

  // The API half first: a seed track answers a mix on either engine.
  // `adventurousness` spelled out because the contract marks it
  // required: the server defaults it to 0.4 and the hand-typed body this
  // replaced left it off, so the suite has been asking for a mix the app
  // itself would not ask for.
  const mix = await app.api.post('/mixes/instant', {
    data: { seedPid: pid, size: 20, adventurousness: 0.4 },
  });
  expect(['metadata', 'sonic']).toContain(mix.basis);
  expect(mix.items.length).toBeGreaterThan(0);
  expect(mix.excluded, 'nothing was excluded, so nothing counts').toBe(0);

  // Asked again with everything it just answered excluded, the count
  // says why the result thinned out: the candidates were met and
  // dropped, which is what lets the app tell "already queued" apart
  // from "no mix exists".
  const excludePids = [pid, ...mix.items.map((it) => it.pid)];
  const rerun = await app.api.post('/mixes/instant', {
    data: { seedPid: pid, size: 20, adventurousness: 0.4, excludePids },
  });
  expect(rerun.excluded).toBeGreaterThan(0);
  for (const it of rerun.items) {
    expect(excludePids).not.toContain(it.pid);
  }

  // The browser journey: play the seed from the tracks index, open
  // Discover, run the mix with the default adventurousness. A row on
  // the index plays the whole listing from that row, so the exclusion -
  // the current track and what is still coming - leaves the rows above
  // the seed mixable. On this library those rows are the only mixable
  // tracks there are: any mix at all is drawn from played history,
  // which is the reopened pool this spec pins. Paused at once so the
  // second-long fixture tracks cannot march the queue while it runs.
  await app.nav.enter('tracks');
  await app.music.play(pid);
  await app.player.pause();
  await app.discovery.runInstantMix();

  // A mix started from a playing track lands behind it. Nothing is
  // replaced and nothing is pushed - the track that was playing is
  // still playing - so the message the sheet leaves is the only way to
  // what changed; an empty mix leaves a plain sentence with no Open,
  // so this visibility is the assertion an empty mix fails.
  const open = app.discovery.queueFromMessage();
  await expect(open).toBeVisible({ timeout: T.nav });
  await open.click();

  // The queue, over the player: what was playing still holds the
  // current row, and the mix is behind what the listing queued.
  await expect(app.queue.screen()).toBeVisible({ timeout: T.nav });
  expect(
    await app.queue.upNextCount(),
    'the mix is queued behind what is playing',
  ).toBeGreaterThan(0);
});

test('sonic coverage answers similar tracks and a sonic path', async ({ app }) => {
  test.setTimeout(J.long);
  await app.seed.sonicCoverage();

  const charlie = (await app.seed.item('Charlie Song')).pid;
  const delta = (await app.seed.item('Delta Song')).pid;

  const similar = await app.api.get('/items/{pid}/similar', { path: { pid: charlie } });
  expect(similar.basis).toBe('sonic');
  expect(similar.items.length).toBeGreaterThan(0);
  expect(similar.items.map((it) => it.pid)).not.toContain(charlie);

  // The same answer through the browser, on a seed the call above has
  // just proved has neighbours: the list screen and the basis chip it
  // draws are shared with the instant mix, which reaches them from the
  // home shelf rather than from the player.
  await app.nav.enter('tracks');
  await app.music.play(charlie);
  await app.discovery.runSimilarTracks();
  await expect(app.discovery.basis('similar')).toHaveText(
    /^Answered by the (metadata|sonic) engine$/,
  );

  const path = await app.api.get('/mixes/path', {
    query: { from: charlie, to: delta },
  });
  expect(typeof path.complete).toBe('boolean');
  expect(path.items.length).toBeGreaterThanOrEqual(2);
  expect(path.items[0].pid).toBe(charlie);
  // On this tiny dense library the graph usually connects, but an
  // incomplete prefix is a legal answer and not worth a flake.
  if (path.complete) {
    expect(path.items[path.items.length - 1].pid).toBe(delta);
  }
});

test('the worker API is gated by the worker token', async ({ app, anonApi }) => {
  test.setTimeout(J.long);

  // Nobody at all, on a connection that has never logged in: what a
  // worker that forgot its credential looks like. Not `app.api.as('')`,
  // which drops the bearer but keeps this test's cookie jar - the
  // difference does not bite here today and is exactly the sort of thing
  // that starts biting once a neighbouring line logs in.
  const refused = await anonApi.raw.get('/similarity/work');
  expect(refused.status()).toBe(401);

  // Lease only after the embedded analyzer drained the queue: a lease
  // taken earlier would hide queue rows from it for the lease term and
  // stall coverage for the whole suite.
  await app.seed.sonicCoverage();
  const batch = await app.api.as(WORKER_TOKEN).get('/similarity/work', {
    query: { limit: 5 },
  });
  expect(Array.isArray(batch.items)).toBe(true);
  expect(batch.items.length).toBe(0);
  expect(batch.retryAfterSeconds).toBeGreaterThan(0);
});

test('a csv import resolves fixture tracks and exports portable refs', async ({ app }) => {
  const payload = [
    'artist,title,album',
    'Fixture Artist,Alpha Song,Fixture Album',
    'Nonexistent Artist,No Such Song,Nowhere Album',
  ].join('\n');
  const report = await app.api.post('/playlists/import', {
    data: { source: 'csv', name: 'CSV Import e2e', payload },
  });
  expect(report.requested).toBe(2);
  expect(report.resolved).toBe(1);
  expect(report.missing.length).toBe(1);
  expect(report.missing[0].title).toBe('No Such Song');
  expect(report.rungs.descriptive).toBe(1);
  expect(report.playlistPid, 'the import reports the playlist it made').toMatch(/^pl-/);
  const pid = report.playlistPid!;
  try {
    const entries = await app.api.get('/playlists/{pid}/items', { path: { pid } });
    expect(entries.entries.map((e) => e.item.title)).toEqual(['Alpha Song']);

    const exported = await app.api.get('/playlists/{pid}/portable', { path: { pid } });
    expect(exported.name).toBe('CSV Import e2e');
    expect(exported.refs.length).toBe(1);
    expect(exported.refs[0].title).toBe('Alpha Song');
    expect(exported.refs[0].artist).toBe('Fixture Artist');
  } finally {
    // Deleted rather than reused by name: the import is what is under
    // test here, so it has to run afresh on a stack this test has
    // already used - a resolved-count of one against a playlist that
    // already held the track would pass without importing anything.
    await app.api.delete('/playlists/{pid}', { path: { pid } });
  }
});
