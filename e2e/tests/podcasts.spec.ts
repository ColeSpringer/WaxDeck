import { test, expect, APIRequestContext } from './fixtures';
import {
  ADMIN_PASS,
  ADMIN_USER,
  authed,
  clickInView,
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

// The backlog the server counts for this caller, which the tile draws.
async function serverUnplayed(
  request: APIRequestContext,
  token: string,
  showPid: string,
): Promise<number> {
  const resp = await request.get('/api/v1/podcasts', authed(token));
  expect(resp.ok()).toBeTruthy();
  const hit = ((await resp.json()).items ?? []).find(
    (s: any) => s.show.pid === showPid,
  );
  expect(typeof hit?.unplayedCount, 'a subscription carries its backlog').toBe(
    'number',
  );
  return hit.unplayedCount as number;
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
  const showTile = page.locator(sem(SemanticsIds.podcast(showPid)));
  await showTile.waitFor({ timeout: 30_000 });

  // The tile draws the count the server reports, not the feed's three
  // episodes: a backlog is per-caller, and the gpodder spec plays this
  // same feed as this same account. Re-read each attempt, since a
  // checkpoint from another device invalidates the grid.
  await expect(async () => {
    const backlog = await serverUnplayed(request, token, showPid);
    expect(backlog, 'a fresh subscription has something waiting').toBeGreaterThan(0);
    await expect(showTile).toHaveAccessibleName(new RegExp(`\\b${backlog} unplayed\\b`), {
      timeout: 2_000,
    });
  }).toPass({ timeout: 30_000 });
  // The show screen is on screen once its follow control is: the header
  // draws it, and it is the one control the hub does not have.
  const episodeList = () => page.locator(sem(SemanticsIds.podcastUnsubscribe));

  // Silence trimming is a per-subscription setting; flip it before
  // playback so the session starts trimming from the first load.
  const put = await request.put(`/api/v1/podcasts/${showPid}/settings`, {
    ...authed(token),
    data: { trimSilence: true },
  });
  expect(put.ok()).toBeTruthy();

  await clickThrough(showTile, episodeList());

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
  await clickThrough(page.getByRole('button', { name: 'Back' }).first(), showTile);
  // Arrival is the follow control, never a row: the hub's shelves carry
  // the same row identifiers, and clickThrough skips its click when the
  // destination already shows, so a row alone never leaves the hub.
  await clickThrough(showTile, episodeList());
  const episodeRow = page.locator(sem(SemanticsIds.episode(episode.pid)));
  await episodeRow.waitFor({ timeout: 30_000 });

  // Play it. The trim chip reports time actually saved once the
  // session seeks over the lead silence, which is the observable proof
  // the jump happened (positions stay honest, so only the counter can
  // tell trimmed playback from ordinary playback this quickly).
  // clickInView, not clickThrough: an episode row sits directly under
  // the filter chips, and a forced click against a rect read while the
  // list was still settling lands on a chip instead. Selecting
  // "Downloaded" there removes the episode the click was aimed at, so
  // every retry then clicks a row that is no longer in the list and the
  // step spins out its whole budget. clickInView re-reads the box each
  // attempt and refuses to click until it is fully in view.
  await clickInView(page, episodeRow, {
    // The list scrolls under a fixed header, so a row past the first is
    // below the fold; the search field is a stable place inside the same
    // scroll view to put the cursor before wheeling.
    surface: page.locator(sem(SemanticsIds.showEpisodeSearch)),
    settled: page.locator(sem(SemanticsIds.playerToggle)),
  });
  await page.locator(sem(SemanticsIds.playerToggle)).waitFor({ timeout: 30_000 });
  await expect(page.locator(sem(SemanticsIds.playerTrim))).toBeVisible({ timeout: 15_000 });
  await expect(page.locator(sem(SemanticsIds.playerTrim))).toHaveAccessibleName(/saved/, {
    timeout: 30_000,
  });

  // The speed sheet reaches any rate in one tap and remembers it for the
  // show. 1.5x from 1x is two presets away, which the cycling button it
  // replaced could only walk to.
  await clickThrough(
    page.locator(sem(SemanticsIds.playerSpeed)),
    page.locator(sem(SemanticsIds.playerSpeedSheet)),
  );
  await page.locator(sem(SemanticsIds.playerSpeedPreset(150))).click({ force: true });
  await expect(page.locator(sem(SemanticsIds.playerSpeed))).toHaveAccessibleName(/1\.5x/, {
    timeout: 15_000,
  });
  // Per show, on the server, not just for this session.
  await expect
    .poll(
      async () => {
        const resp = await request.get(`/api/v1/podcasts/${showPid}`, authed(token));
        if (!resp.ok()) return 0;
        return ((await resp.json()).settings?.speed ?? 0) as number;
      },
      { timeout: 30_000, message: 'the chosen speed should be remembered for the show' },
    )
    .toBeCloseTo(1.5, 2);

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
  // The player's own way out, by handle. It used to be an app-bar back
  // button called "Back" and it is a collapse chevron called "Collapse
  // player" since the rebuild onto the scaffold, so a name match here
  // walks past the player onto the screen underneath - which is the
  // failure radio-cast.spec records as "how this scenario started
  // popping the wrong screen".
  await clickThrough(
    page.locator(sem(SemanticsIds.playerBack)),
    page.locator(sem(SemanticsIds.episodeInfo(episode.pid))),
  );
  await clickThrough(
    page.locator(sem(SemanticsIds.episodeInfo(episode.pid))),
    page.getByText(/pilot episode/).first(),
  );

  // The episode's location carries its show, which is what lets it be
  // gone to rather than pushed: the address bar follows the hop, and the
  // link a listener copies here opens the episode with its show under
  // it. Leaving lands back on the show for the same reason.
  await expect(page).toHaveURL(new RegExp(`/podcasts/${showPid}/episodes/${episode.pid}$`));
  await clickThrough(
    page.getByRole('button', { name: 'Back' }).first(),
    page.locator(sem(SemanticsIds.podcastUnsubscribe)),
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
  // carries `catalog-busy`, clears on its own, and is retried; the
  // in-use refusal, which is the one this step is actually about,
  // carries `conflict`, does not clear, and fails here with the server's
  // own message and the play state that produced it.
  await expect
    .poll(
      async () => {
        const resp = await request.delete(`/api/v1/episodes/${second.pid}/fetch`, authed(token));
        if (resp.status() === 204) return 204;
        const body = await resp.text();
        // Parsed defensively: anything that is not the structured error
        // body falls through to the failure below with its text intact.
        let code = '';
        try {
          code = (JSON.parse(body) as { code?: string }).code ?? '';
        } catch {
          code = '';
        }
        if (resp.status() === 409 && code === 'catalog-busy') return 409;
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

  // The client half of passthrough: an episode this server holds no
  // bytes for plays from the row rather than queueing a fetch. The
  // third episode has never been fetched, so nothing but the relay can
  // be answering. The show list is stale about the removal above, so it
  // is reloaded first.
  const third = items[2];
  await clickThrough(
    page.getByRole('button', { name: 'Back' }).first(),
    showTile,
  );
  // Follow control again: a row alone would be satisfied by the hub.
  await clickThrough(showTile, episodeList());
  const thirdRow = page.locator(sem(SemanticsIds.episode(third.pid)));
  await thirdRow.waitFor({ timeout: 30_000 });
  // Same hazard as the first play above, and the same answer.
  await clickInView(page, thirdRow, {
    surface: page.locator(sem(SemanticsIds.showEpisodeSearch)),
    settled: page.locator(sem(SemanticsIds.playerToggle)),
  });
  await page.locator(sem(SemanticsIds.playerToggle)).waitFor({ timeout: 30_000 });
  const relayed = await request.get(`/api/v1/items/${third.pid}/play-info`, authed(token));
  expect(relayed.status(), 'a never-fetched episode still mints a URL').toBe(200);
  expect((await relayed.json()).url as string).toContain('/media/enclosure?');
  // It is really playing, which is the part the row's tap is about: the
  // fetch-wait path would have left the player empty and queued a
  // download instead.
  await expect(page.locator(sem(SemanticsIds.playerToggle))).toHaveAccessibleName(
    /Pause/,
    { timeout: 30_000 },
  );

  // Unsubscribing while an episode sits fetched asks about the server
  // files; keeping them ends the subscription and leaves the download
  // governed by whoever subscribes next. The player is still up from the
  // passthrough check, so leaving it is the player's control (see above).
  await clickThrough(
    page.locator(sem(SemanticsIds.playerBack)),
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
