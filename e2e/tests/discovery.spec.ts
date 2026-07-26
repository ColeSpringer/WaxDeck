import { test, expect, APIRequestContext, Page } from './fixtures';
import { authed, clickThrough, ensureAdmin, typeInto, waitForLibrary } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The discovery slice over the real stack: an instant mix started from
// a playing track in the browser, the sonic surfaces (similar tracks
// and paths) once the embedded analyzer has swept the fixture library,
// the worker API's token gate, and the streaming-service playlist
// import round trip with its portable export.


// Matches the token run-stack.sh hands the server.
const WORKER_TOKEN = 'e2e-worker-token';

async function login(page: Page) {
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, 'admin');
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), 'wax-e2e-pass');
  await page.getByRole('button', { name: 'Log in' }).click();
  await page.locator(sem(SemanticsIds.playlistsOpen)).waitFor({ timeout: 30_000 });
}

async function trackPid(
  request: APIRequestContext,
  token: string,
  title: string,
): Promise<string> {
  const search = await (
    await request.get(
      `/api/v1/library/search?q=${encodeURIComponent(title)}`,
      authed(token),
    )
  ).json();
  const hit = (search.tracks as Array<{ pid: string; title: string }>).find(
    (t) => t.title === title,
  );
  expect(hit, `the fixture track "${title}" is indexed`).toBeTruthy();
  return hit!.pid;
}

// The embedded analyzer's first pass starts about 45 seconds after
// server boot and drains the small fixture queue quickly once running,
// so this polls patiently. Requiring both an embedding and an empty
// queue distinguishes "finished" from "not started yet" (before the
// first sweep the queue is empty with zero coverage).
async function waitForSonicCoverage(request: APIRequestContext, token: string) {
  await expect
    .poll(
      async () => {
        const resp = await request.get('/api/v1/similarity/status', authed(token));
        if (!resp.ok()) return false;
        const st = await resp.json();
        return st.embeddedTracks > 0 && st.queueDepth === 0;
      },
      {
        timeout: 120_000,
        intervals: [2_000],
        message: 'the embedded analyzer should sweep the fixture library',
      },
    )
    .toBeTruthy();
}

test('an instant mix starts from any playing track', async ({ page, request }) => {
  test.setTimeout(120_000);
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const pid = await trackPid(request, token, 'Bravo Song');

  // The API half first: a seed track answers a mix on either engine.
  const mixed = await request.post('/api/v1/mixes/instant', {
    ...authed(token),
    data: { seedPid: pid, size: 20 },
  });
  expect(mixed.status()).toBe(200);
  const mix = await mixed.json();
  expect(['metadata', 'sonic']).toContain(mix.basis);
  expect(mix.items.length).toBeGreaterThan(0);

  // The browser journey: play the track, open Discover, run the mix
  // with the default adventurousness.
  await login(page);
  const card = page.locator(sem(SemanticsIds.item(pid)));
  await card.waitFor({ timeout: 30_000 });
  await clickThrough(card, page.locator(sem(SemanticsIds.playerToggle)));
  await clickThrough(page.locator(sem(SemanticsIds.playerDiscover)), page.locator(sem(SemanticsIds.instantMix)));
  await clickThrough(page.locator(sem(SemanticsIds.instantMix)), page.locator(sem(SemanticsIds.instantMixRun)));

  // The sheet closes only once the mix came back; a swallowed click
  // retries until it does.
  const run = page.locator(sem(SemanticsIds.instantMixRun));
  await expect(async () => {
    if (await run.isVisible()) {
      await run.click({ timeout: 2_000, force: true }).catch(() => {});
    }
    await expect(run).toBeHidden({ timeout: 5_000 });
  }).toPass({ timeout: 30_000 });

  // Confirming pushes the mix list and a player for its first track on
  // top. The seed is never in its own mix, so the seed title vanishing
  // proves the new player is up before popping back onto the list.
  await expect(page.getByText('Bravo Song', { exact: true })).toHaveCount(0, {
    timeout: 15_000,
  });
  await clickThrough(
    page.getByRole('button', { name: 'Back' }).first(),
    page.locator(sem(SemanticsIds.scopedItem('mix', 0))),
  );
  await expect(page.getByText('Instant mix', { exact: true }).first()).toBeVisible();
  // The basis chip reports whichever engine answered; coverage may or
  // may not have landed by the time this spec runs. The chip surfaces
  // in the semantics tree as a checkbox named for the basis.
  await expect(
    page.getByRole('checkbox', { name: /^(metadata|sonic)$/ }),
  ).toBeVisible();
});

test('sonic coverage answers similar tracks and a sonic path', async ({ request }) => {
  test.setTimeout(180_000);
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await waitForSonicCoverage(request, token);

  const charlie = await trackPid(request, token, 'Charlie Song');
  const delta = await trackPid(request, token, 'Delta Song');

  const similar = await request.get(
    `/api/v1/items/${charlie}/similar`,
    authed(token),
  );
  expect(similar.status()).toBe(200);
  const sim = await similar.json();
  expect(sim.basis).toBe('sonic');
  expect(sim.items.length).toBeGreaterThan(0);
  expect(sim.items.map((it: { pid: string }) => it.pid)).not.toContain(charlie);

  const path = await request.get(
    `/api/v1/mixes/path?from=${charlie}&to=${delta}`,
    authed(token),
  );
  expect(path.status()).toBe(200);
  const body = await path.json();
  expect(typeof body.complete).toBe('boolean');
  expect(body.items.length).toBeGreaterThanOrEqual(2);
  expect(body.items[0].pid).toBe(charlie);
  // On this tiny dense library the graph usually connects, but an
  // incomplete prefix is a legal answer and not worth a flake.
  if (body.complete) {
    expect(body.items[body.items.length - 1].pid).toBe(delta);
  }
});

test('the worker API is gated by the worker token', async ({ request }) => {
  test.setTimeout(180_000);
  const token = await ensureAdmin(request);

  const refused = await request.get('/api/v1/similarity/work');
  expect(refused.status()).toBe(401);

  // Lease only after the embedded analyzer drained the queue: a lease
  // taken earlier would hide queue rows from it for the lease term and
  // stall coverage for the whole suite.
  await waitForLibrary(request, token);
  await waitForSonicCoverage(request, token);
  const work = await request.get('/api/v1/similarity/work?limit=5', {
    headers: { Authorization: `Bearer ${WORKER_TOKEN}` },
  });
  expect(work.status()).toBe(200);
  const batch = await work.json();
  expect(Array.isArray(batch.items)).toBe(true);
  expect(batch.items.length).toBe(0);
  expect(batch.retryAfterSeconds).toBeGreaterThan(0);
});

test('a csv import resolves fixture tracks and exports portable refs', async ({
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  const payload = [
    'artist,title,album',
    'Fixture Artist,Alpha Song,Fixture Album',
    'Nonexistent Artist,No Such Song,Nowhere Album',
  ].join('\n');
  const imported = await request.post('/api/v1/playlists/import', {
    ...authed(token),
    data: { source: 'csv', name: 'CSV Import e2e', payload },
  });
  expect(imported.status()).toBe(200);
  const report = await imported.json();
  expect(report.requested).toBe(2);
  expect(report.resolved).toBe(1);
  expect(report.missing.length).toBe(1);
  expect(report.missing[0].title).toBe('No Such Song');
  expect(report.rungs.descriptive).toBe(1);
  expect(report.playlistPid).toMatch(/^pl-/);

  try {
    const entries = await (
      await request.get(`/api/v1/playlists/${report.playlistPid}/items`, authed(token))
    ).json();
    expect(
      entries.entries.map((e: { item: { title: string } }) => e.item.title),
    ).toEqual(['Alpha Song']);

    const portable = await request.get(
      `/api/v1/playlists/${report.playlistPid}/portable`,
      authed(token),
    );
    expect(portable.status()).toBe(200);
    const exported = await portable.json();
    expect(exported.name).toBe('CSV Import e2e');
    expect(exported.refs.length).toBe(1);
    expect(exported.refs[0].title).toBe('Alpha Song');
    expect(exported.refs[0].artist).toBe('Fixture Artist');
  } finally {
    await request.delete(`/api/v1/playlists/${report.playlistPid}`, authed(token));
  }
});
