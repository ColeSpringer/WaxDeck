import { test, expect } from './fixtures';
import { T, clickUntilRequested } from './driver';

// Switching items mid-play must replace what the engine is playing.
// just_audio's web backend caches source players by playlist id, and the
// playlist the 0.10 API funnels every load through keeps one id for the
// player's whole life - so a second load on a live player found the
// stale cached player, kept the old element's src, applied the new
// initial position as a bare seek, and reported success: the old item
// played on under the new item's face while the new session checkpointed
// against it. The engine stops the platform player before every
// replacement now; this spec pins the observable half of that promise -
// the switched-to item's media is actually fetched.
test('switching tracks mid-play fetches the new media', async ({ app, page }) => {
  // The tracks index, and the first two rows it actually draws: a lazy
  // list only builds what its viewport holds, so the pair is read off
  // the screen rather than assumed from any listing order. Which two
  // tracks they are does not matter - the stale-player path triggered
  // on every load issued while the platform was still active, mid-play
  // or already run out (completed is not idle), so the fixtures'
  // few-second lengths do not matter either.
  await app.nav.enter('tracks');
  const pids = await app.music.visiblePids('tr');
  expect(pids.length, 'the tracks index lists at least two tracks').toBeGreaterThan(1);
  const [a, b] = pids;

  // Play the first track and see its media actually fetched.
  const mediaA = page.waitForRequest(
    (req) => req.url().includes('/media/') && req.url().includes(`pid=${a}`),
    { timeout: T.nav },
  );
  await app.music.play(a);
  await mediaA;

  // Tap the second track and hold the switch to its promise: the engine
  // fetches the new media. Before the stop-first fix the web player
  // reported success while keeping the old stream loaded - the first
  // item played on (or replayed) under the second item's face - and
  // this request never happened.
  //
  // Play lands in the dock, so the listing and its second row never
  // left the screen - but the deck bar the play gesture settles on is
  // already up from the first track, so the click is retried with the
  // media request itself as the goal that proves it landed. A repeated
  // click merely restarts the same track.
  await clickUntilRequested(
    page,
    app.music.item(b),
    (req) => req.url().includes('/media/') && req.url().includes(`pid=${b}`),
  );
});
