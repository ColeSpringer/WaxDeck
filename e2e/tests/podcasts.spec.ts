import { test, expect, APIRequestContext } from './fixtures';
import {
  ADMIN_PASS,
  ADMIN_USER,
  authed,
  clickThrough,
  ensureAdmin,
  typeInto,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The podcast journey: subscribe to the fixture feed host through the
// web UI, fetch an episode to the server, and play it with silence
// trimming saving real time. The feed host (feedserv) serves a
// generated three-episode feed whose audio carries lead silence.

const FEED_URL = 'http://127.0.0.1:4421/feed.xml';

async function subscribedShowPid(request: APIRequestContext, token: string): Promise<string> {
  let pid = '';
  await expect
    .poll(
      async () => {
        const resp = await request.get('/api/v1/podcasts', authed(token));
        if (!resp.ok()) return false;
        const items = (await resp.json()).items ?? [];
        const hit = items.find((s: any) => s.show.feedUrl === FEED_URL);
        if (!hit) return false;
        pid = hit.show.pid;
        return true;
      },
      { timeout: 30_000, message: 'the subscription should appear' },
    )
    .toBeTruthy();
  return pid;
}

test('subscribe, fetch, and play an episode with silence trimming', async ({ page, request }) => {
  test.setTimeout(240_000);
  const token = await ensureAdmin(request);

  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();

  // Subscribe through the UI: podcasts screen, add dialog, feed URL.
  // The dialog open retries as a unit: a click over canvas can be
  // swallowed while flutter's handlers are still attaching (the click
  // cousin of the keystroke gap typeInto retries around), and a
  // swallowed click here means the dialog never appears at all.
  await page.locator(sem(SemanticsIds.navDestination('podcasts'))).click();
  await expect(async () => {
    await page.locator(sem(SemanticsIds.podcastAdd)).click();
    await page
      .locator(sem(SemanticsIds.podcastSubscribeConfirm))
      .waitFor({ timeout: 5_000 });
  }).toPass({ timeout: 30_000 });
  await typeInto(page, page.getByRole('textbox', { name: 'Feed or channel URL' }), FEED_URL);
  await page.locator(sem(SemanticsIds.podcastSubscribeConfirm)).click();

  const showPid = await subscribedShowPid(request, token);
  const showRow = page.locator(sem(SemanticsIds.podcast(showPid)));
  await showRow.waitFor({ timeout: 30_000 });
  const episodeList = () => page.locator(sem(SemanticsIds.podcastUnsubscribe));

  // Silence trimming is a per-subscription setting; flip it before
  // playback so the session starts trimming from the first load.
  const put = await request.put(`/api/v1/podcasts/${showPid}/settings`, {
    ...authed(token),
    data: { trimSilence: true },
  });
  expect(put.ok()).toBeTruthy();

  await clickThrough(showRow, episodeList());

  // Three episodes from the generated feed, none fetched yet.
  const eps = await request.get(`/api/v1/podcasts/${showPid}/episodes`, authed(token));
  expect(eps.ok()).toBeTruthy();
  const items = (await eps.json()).items as any[];
  expect(items.length).toBe(3);
  const episode = items[0];
  expect(episode.downloaded).toBeFalsy();

  // Queue the server-side fetch from the UI; the background worker
  // lands it and the row flips to downloaded.
  await page.locator(sem(SemanticsIds.episodeFetch(episode.pid))).click();
  await expect
    .poll(
      async () => {
        const resp = await request.get(`/api/v1/podcasts/${showPid}/episodes`, authed(token));
        const fresh = ((await resp.json()).items as any[]).find((e) => e.pid === episode.pid);
        return fresh?.downloaded ?? false;
      },
      { timeout: 60_000, message: 'the fetch worker should land the episode' },
    )
    .toBeTruthy();

  // The skip map builds in the background off the streaming sidecar's
  // analysis; asking for it queues the work.
  await expect
    .poll(
      async () => {
        const resp = await request.get(`/api/v1/items/${episode.pid}/skip-map`, authed(token));
        if (!resp.ok()) return 'error';
        return (await resp.json()).state as string;
      },
      { timeout: 90_000, message: 'silence analysis should produce the skip map' },
    )
    .toBe('ready');
  const map = await (await request.get(`/api/v1/items/${episode.pid}/skip-map`, authed(token))).json();
  expect((map.spans ?? []).length).toBeGreaterThan(0);

  // The show screen rendered while the fetch was still queued;
  // re-entering it reloads the list with the episode present. Back
  // travels through the app's own button: browser history against
  // flutter's navigator is handled asynchronously, and a deferred
  // popstate can pop the very screen the test just re-entered.
  await clickThrough(page.getByRole('button', { name: 'Back' }).first(), showRow);
  await clickThrough(showRow, page.locator(sem(SemanticsIds.episode(episode.pid))));

  // Play it. The trim chip reports time actually saved once the
  // session seeks over the lead silence, which is the observable proof
  // the jump happened (positions stay honest, so only the counter can
  // tell trimmed playback from ordinary playback this quickly).
  await clickThrough(
    page.locator(sem(SemanticsIds.episode(episode.pid))),
    page.locator(sem(SemanticsIds.playerToggle)),
  );
  await expect(page.locator(sem(SemanticsIds.playerTrim))).toBeVisible({ timeout: 15_000 });
  await expect(page.locator(sem(SemanticsIds.playerTrim))).toHaveAccessibleName(/saved/, {
    timeout: 30_000,
  });

  // Playback is deliberately left running through the rest of this
  // spec. Stopping it was tried and is not worth it: the pause control
  // sits under a sibling semantics node that intercepts the click for as
  // long as the player screen is up, and the reason to stop it did not
  // survive diagnosis anyway. An episode row enqueues that one episode
  // (`QueueSourceKind.single`), so episode one finishing cannot advance
  // into episode two and leave the play state the unfetch step used to
  // be blamed for. What actually refuses that step is a job lease, and
  // the poll below is where that is handled.

  // Show notes were sanitized server-side and render as text.
  await clickThrough(
    page.getByRole('button', { name: 'Back' }).first(),
    page.locator(sem(SemanticsIds.episodeInfo(episode.pid))),
  );
  await clickThrough(
    page.locator(sem(SemanticsIds.episodeInfo(episode.pid))),
    page.getByText(/pilot episode/).first(),
  );

  // The fetch's inverse: a second episode fetches, removes (archive,
  // not delete), and falls back to streaming the feed's own enclosure
  // through this origin rather than refusing.
  const second = items[1];
  const fetch2 = await request.post(`/api/v1/episodes/${second.pid}/fetch`, authed(token));
  expect(fetch2.status()).toBe(202);
  await expect
    .poll(
      async () => {
        const resp = await request.get(`/api/v1/podcasts/${showPid}/episodes`, authed(token));
        const fresh = ((await resp.json()).items as any[]).find((e) => e.pid === second.pid);
        return fresh?.downloaded ?? false;
      },
      { timeout: 60_000 },
    )
    .toBeTruthy();
  // The unfetch can lose a race that is nothing to do with podcasts:
  // it ends in a delete under the shared file-mutation job lease, and
  // this suite runs four workers against one server, so a sibling spec's
  // upload, rescan, or trash round trip can be holding it. That refusal
  // clears on its own and is retried; the in-use refusal, which is the
  // one this step is actually about, is not, and fails here with the
  // server's own message and the play state that produced it.
  await expect
    .poll(
      async () => {
        const resp = await request.delete(`/api/v1/episodes/${second.pid}/fetch`, authed(token));
        if (resp.status() === 204) return 204;
        const body = await resp.text();
        if (resp.status() === 409 && body.includes('conflicting catalog job')) return 409;
        const state = await request.get(
          `/api/v1/items/${second.pid}/play-state`,
          authed(token),
        );
        throw new Error(
          `unfetch answered ${resp.status()}: ${body}\nplay-state: ${await state.text()}`,
        );
      },
      { timeout: 30_000, message: 'the unfetch should succeed once the catalog lease frees' },
    )
    .toBe(204);
  const after = await request.get(`/api/v1/podcasts/${showPid}/episodes`, authed(token));
  const secondAfter = ((await after.json()).items as any[]).find((e) => e.pid === second.pid);
  expect(secondAfter.downloaded).toBeFalsy();
  const info = await request.get(`/api/v1/items/${second.pid}/play-info`, authed(token));
  expect(info.status(), 'a removed episode still streams by enclosure passthrough').toBe(200);
  const passthrough = (await info.json()).url as string;
  expect(passthrough, 'passthrough resolves to the relay, not the engine').toContain(
    '/media/enclosure?',
  );
  // The relay really carries the feed host's bytes, and it carries
  // ranges, which is what makes an unfetched episode scrubbable.
  const ranged = await request.get(passthrough, { headers: { Range: 'bytes=0-99' } });
  expect(ranged.status(), 'the relay forwards the range upstream').toBe(206);
  expect((await ranged.body()).length).toBe(100);

  // Unsubscribing while an episode sits fetched asks about the server
  // files; keeping them ends the subscription and leaves the download
  // governed by whoever subscribes next.
  await clickThrough(
    page.getByRole('button', { name: 'Back' }).first(),
    page.locator(sem(SemanticsIds.podcastUnsubscribe)),
  );
  await expect(async () => {
    await page.locator(sem(SemanticsIds.podcastUnsubscribe)).click();
    await page.locator(sem(SemanticsIds.unsubscribeKeepFiles)).waitFor({ timeout: 5_000 });
  }).toPass({ timeout: 30_000 });
  await page.locator(sem(SemanticsIds.unsubscribeKeepFiles)).click();
  await page.locator(sem(SemanticsIds.podcastSubscribe)).waitFor({ timeout: 30_000 });
  const subs = await request.get('/api/v1/podcasts', authed(token));
  const gone = ((await subs.json()).items ?? []).find((s: any) => s.show.pid === showPid);
  expect(gone, 'the subscription should be gone').toBeFalsy();
  const kept = await request.get(`/api/v1/podcasts/${showPid}/episodes`, authed(token));
  const firstKept = ((await kept.json()).items as any[]).find((e) => e.pid === episode.pid);
  expect(firstKept.downloaded, 'keeping files leaves the fetched episode').toBeTruthy();
});
