import { test, expect } from './fixtures';
import { J } from './driver';

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

  // The browser journey: play the track, open Discover, run the mix
  // with the default adventurousness.
  await app.nav.enter('tracks');
  await app.music.play(pid);
  await app.discovery.runInstantMix();

  // Confirming pushes the mix list and a player for its first track on
  // top. The seed is never in its own mix, so the seed title vanishing
  // proves the new player is up before popping back onto the list.
  await expect(app.discovery.text('Bravo Song', { exact: true })).toHaveCount(0);

  // The player's own control, by handle: it is a collapse chevron named
  // "Collapse player" since the rebuild onto the scaffold, so a match on
  // "Back" finds the mix list's button underneath and pops that instead.
  await app.player.collapse(app.discovery.item('mix', 0));
  await expect(app.discovery.text('Instant mix', { exact: true })).toBeVisible();

  // The basis chip reports whichever engine answered; coverage may or
  // may not have landed by the time this spec runs.
  await expect(app.discovery.basis('mix')).toHaveText(
    /^Answered by the (metadata|sonic) engine$/,
  );
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
