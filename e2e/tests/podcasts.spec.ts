import { test, expect } from './fixtures';
import { J, T, retryCatalogBusy } from './driver';

// The podcast domain over the real stack. The feed host (feedserv)
// serves a generated three-episode feed whose audio carries lead
// silence.
//
// This was one 304-line journey. It is five tests now, by the rule that
// a scenario stays whole only when each step consumes state the previous
// UI step produced and the seam is the assertion. Subscribing, fetching
// and playing are that: the fetch is of the episode the subscription
// found, and the trim chip only means something on the episode the fetch
// landed. Choosing a speed preset, unfetching, reading an episode's
// location and unsubscribing are not - each merely needed a subscription
// to exist, which is a precondition, and preconditions are seeded.
//
// Every test owns its account, so a subscription made here is nobody
// else's, and the backlog the tile draws is exactly the feed's.

const FEED_URL = 'http://127.0.0.1:4421/feed.xml';

test('subscribe, fetch, and play an episode with silence trimming', async ({ app }) => {
  test.setTimeout(J.journey);

  // Subscribing is the first step of the journey, so it goes through the
  // real add dialog rather than the seeder.
  await app.nav.enter('podcasts');
  await app.podcasts.subscribeViaDialog(FEED_URL);

  // Polled: the dialog returns as soon as the request is away, and the
  // server catalogs the show and parses its feed after that.
  let showPid = '';
  await expect
    .poll(
      async () => {
        const subs = await app.api.tryGet('/podcasts');
        const show = (subs?.items ?? []).find((s) => s.show.feedUrl === FEED_URL);
        if (show === undefined) return false;
        showPid = show.show.pid;
        return true;
      },
      { timeout: T.fetch, message: 'the subscription should appear' },
    )
    .toBeTruthy();

  // Exactly the feed's three episodes, because this account has played
  // none of them. The old assertion could only ask the server what it
  // thought the backlog was and compare the tile against that, since a
  // sibling spec played the same feed as the same login.
  // The nav tier, not the assert tier: the tile is drawn from a feed the
  // server is still fetching, parsing and ingesting when the dialog
  // closes, which is a longer wait than a value settling.
  await expect(app.podcasts.show(showPid)).toHaveAccessibleName(/\b3 unplayed\b/, {
    timeout: T.nav,
  });

  // Silence trimming is a per-subscription setting, and this test is
  // about what playback does with it rather than how it is chosen.
  await app.seed.podcastSettings(showPid, { trimSilence: true });

  await app.podcasts.openShow(showPid);
  const episodes = await app.seed.episodes(showPid);
  expect(episodes.length).toBe(3);
  const episode = episodes[0];
  expect(episode.downloaded).toBeFalsy();

  // Queue the server-side fetch from the UI; the background worker lands
  // it and the row flips to downloaded.
  await app.podcasts.episodeFetch(episode.pid).click();
  await expect
    .poll(
      async () =>
        (await app.seed.episodes(showPid)).find((e) => e.pid === episode.pid)?.downloaded ??
        false,
      { timeout: T.fetch, message: 'the fetch worker should land the episode' },
    )
    .toBeTruthy();

  // The skip map builds in the background off the streaming sidecar's
  // analysis; asking for it queues the work.
  // tryGet: the skip map answers 404 until the analysis is queued and
  // 503 while the catalog is busy, and `expect.poll` fails outright on a
  // callback that throws rather than retrying it.
  await expect
    .poll(
      async () =>
        (await app.api.tryGet('/items/{pid}/skip-map', { path: { pid: episode.pid } }))
          ?.state,
      { timeout: T.analyze, message: 'silence analysis should produce the skip map' },
    )
    .toBe('ready');
  const map = await app.api.get('/items/{pid}/skip-map', { path: { pid: episode.pid } });
  expect((map.spans ?? []).length).toBeGreaterThan(0);

  // The show screen rendered while the fetch was still queued;
  // re-entering it reloads the list with the episode present.
  await app.nav.enter('podcasts');
  await app.podcasts.openShow(showPid);

  // Play it. The trim chip reports time actually saved once the session
  // seeks over the lead silence, which is the observable proof the jump
  // happened - positions stay honest, so only the counter can tell
  // trimmed playback from ordinary playback this quickly.
  await app.podcasts.playEpisode(episode.pid);
  await expect(app.player.trim()).toBeVisible();
  await expect(app.player.trim()).toHaveAccessibleName(/saved/);
});

test('the speed sheet reaches any rate in one tap and remembers it', async ({ app }) => {
  test.setTimeout(J.long);
  const showPid = await app.seed.subscribePodcast(FEED_URL);
  const [episode] = await app.seed.episodes(showPid);

  await app.nav.enter('podcasts');
  await app.podcasts.openShow(showPid);
  // Not fetched first: an episode the server holds no bytes for plays
  // from the row by enclosure passthrough, which the passthrough test
  // proves, and a download here would be four workers' worth of load on
  // a shared catalog lease for a preset this test could set either way.
  await app.podcasts.playEpisode(episode.pid);

  // 1.5x from 1x is two presets away, which the cycling button this
  // replaced could only walk to.
  await app.player.setSpeed(150);
  await expect(app.player.speed()).toHaveAccessibleName(/1\.5x/);

  // Per show, on the server, not just for this session.
  await expect
    .poll(
      async () =>
        (await app.api.tryGet('/podcasts/{pid}', { path: { pid: showPid } }))?.settings
          ?.speed ?? 0,
      { timeout: T.assert, message: 'the chosen speed should be remembered for the show' },
    )
    .toBeCloseTo(1.5, 2);
});

test("an episode's location carries its show", async ({ app }) => {
  test.setTimeout(J.long);
  const showPid = await app.seed.subscribePodcast(FEED_URL);
  const [episode] = await app.seed.episodes(showPid);

  await app.nav.enter('podcasts');
  await app.podcasts.openShow(showPid);

  // Show notes were sanitized server-side and render as text. Opened as
  // a retried unit: Flutter web swallows a click while its handlers are
  // still attaching, and a swallowed one here means the notes never
  // appear at all.
  await app.podcasts.openEpisodeInfo(episode.pid, app.podcasts.text(/pilot episode/));
  await expect(app.podcasts.text(/pilot episode/)).toBeVisible();

  // The episode's location carries its show, which is what lets it be
  // gone to rather than pushed: the address bar follows the hop, and the
  // link a listener copies here opens the episode with its show under
  // it. Leaving lands back on the show for the same reason.
  expect(app.nav.location()).toMatch(
    new RegExp(`/podcasts/${showPid}/episodes/${episode.pid}$`),
  );
  await app.podcasts.back(app.podcasts.unsubscribe());
});

test('an unfetched episode still streams by enclosure passthrough', async ({ app }) => {
  test.setTimeout(J.long);
  const showPid = await app.seed.subscribePodcast(FEED_URL);
  const episodes = await app.seed.episodes(showPid);
  const second = episodes[1];
  const third = episodes[2];
  await app.seed.fetchEpisode(showPid, second.pid);

  // The fetch's inverse: remove (archive, not delete) and fall back to
  // streaming the feed's own enclosure through this origin rather than
  // refusing.
  //
  // The unfetch can lose a race that is nothing to do with podcasts: it
  // ends in a delete under the shared file-mutation job lease, and four
  // workers run against one server, so a sibling spec's upload, rescan
  // or trash round trip can be holding it. That refusal carries
  // `catalog-busy` and clears on its own; the in-use refusal, which is
  // the one this step is about, carries `conflict` and does not.
  await retryCatalogBusy(() =>
    app.api.delete('/episodes/{pid}/fetch', { path: { pid: second.pid } }),
  );
  const after = await app.seed.episodes(showPid);
  expect(after.find((e) => e.pid === second.pid)?.downloaded).toBeFalsy();

  const info = await app.api.get('/items/{pid}/play-info', { path: { pid: second.pid } });
  expect(info.url, 'passthrough resolves to the relay, not the engine').toContain(
    '/media/enclosure?',
  );

  // The relay really carries the feed host's bytes, and it carries
  // ranges, which is what makes an unfetched episode scrubbable.
  const ranged = await app.api.raw.minted(info.url, { headers: { Range: 'bytes=0-99' } });
  expect(ranged.status(), 'the relay forwards the range upstream').toBe(206);
  expect((await ranged.body()).length).toBe(100);

  // The client half of passthrough: an episode this server holds no
  // bytes for plays from the row rather than queueing a fetch. The third
  // episode has never been fetched, so nothing but the relay can be
  // answering.
  await app.nav.enter('podcasts');
  await app.podcasts.openShow(showPid);
  await app.podcasts.playEpisode(third.pid);
  const relayed = await app.api.get('/items/{pid}/play-info', { path: { pid: third.pid } });
  expect(relayed.url, 'a never-fetched episode still mints a relay URL').toContain(
    '/media/enclosure?',
  );
  // It is really playing, which is the part the row's tap is about: the
  // fetch-wait path would have left the player empty and queued a
  // download instead.
  await expect(app.player.toggle()).toHaveAccessibleName(/Pause/);
});

test('unsubscribing while keeping files leaves the fetched episode', async ({ app }) => {
  test.setTimeout(J.long);
  const showPid = await app.seed.subscribePodcast(FEED_URL);
  const [episode] = await app.seed.episodes(showPid);
  await app.seed.fetchEpisode(showPid, episode.pid);

  await app.nav.enter('podcasts');
  await app.podcasts.openShow(showPid);

  // Unsubscribing while an episode sits fetched asks about the server
  // files; keeping them ends the subscription and leaves the download
  // governed by whoever subscribes next.
  await app.podcasts.unsubscribeKeepingFiles();

  const subs = await app.api.get('/podcasts');
  expect(
    (subs.items ?? []).find((s) => s.show.pid === showPid),
    'the subscription should be gone',
  ).toBeFalsy();
  const kept = await app.seed.episodes(showPid);
  expect(
    kept.find((e) => e.pid === episode.pid)?.downloaded,
    'keeping files leaves the fetched episode',
  ).toBeTruthy();
});
