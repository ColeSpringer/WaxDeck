import { test, expect } from './fixtures';
import { T, clickUntilRequested } from './driver';
import { MediaTraffic } from './support/media';

// A minted stream URL carries a short-lived media token (`mt`), and the
// player mints again when a stream is refused or its token has lapsed:
// reactively when a fetch meets the refusal, proactively when its own
// clock says the token is spent before it asks. What it must never do
// is read a refusal as the file and skip the track.
//
// Every fixture track is seconds long and arrives whole in one ranged
// response, so a token cannot catch one mid-listen on its own; the
// traffic support makes the stream that can (see support/media.ts). The
// two re-mint tests hold the long fixture, which plays some six seconds of
// what it was given before it waits on the rest: far enough in that a
// stream minted again and played from the top shows.

/// The long fixture: ten seconds on an album of its own.
const LONG = 'Long Division';

const LAPSED = { code: 'unauthenticated', message: 'invalid or expired media token' };
const ENGINE_AWAY = { code: 'internal', message: 'stream backend unavailable' };

/// The stream minted again, at `url`, plays on from where the listener
/// stood: it begins playing there, not at the top of the item, and moves
/// past it. Read on that stream alone, because the one it replaced got
/// as far as `stoodAt` too, and an element that reloaded from zero
/// passes any reading taken across both.
async function expectResumed(
  traffic: MediaTraffic,
  pid: string,
  url: string,
  stoodAt: number,
): Promise<void> {
  await expect
    .poll(async () => (await traffic.played(pid, url))?.to ?? 0, {
      message: 'the stream minted again should play on',
    })
    .toBeGreaterThan(stoodAt + 0.25);
  const span = (await traffic.played(pid, url))!;
  expect(span.from, `the stream minted again should begin at ${stoodAt.toFixed(2)} s`).toBeGreaterThan(
    stoodAt - 0.25,
  );
  expect(span.from, `the stream minted again should begin at ${stoodAt.toFixed(2)} s`).toBeLessThan(
    stoodAt + 0.5,
  );
}

test('a stream whose token lapsed during a pause is minted again when play meets the refusal', async ({
  app,
}) => {
  const traffic = await MediaTraffic.watch(app.page);
  const { pid } = await app.seed.item(LONG);
  // From the top, whatever a run before left: a resume point would have
  // the player seek into the held stream, which never answers.
  await app.seed.setPosition(pid, 0);

  // It arrives the way a long stream does: still being fetched, with the
  // element waiting on the rest, when its listener pauses.
  const held = await traffic.holdContinuation(pid);
  await app.music.playAlbumOf(pid);
  await expect
    .poll(() => held() !== undefined, {
      message: 'the element should come back for the rest of the stream',
    })
    .toBe(true);
  const stream = held()!;
  // Paused only once the element has played out what it was given and
  // stands waiting on the rest, so the play below waits on the network:
  // the refusal must meet a play that is still pending.
  let last = -1;
  await expect
    .poll(
      async () => {
        const at = (await traffic.position(pid)) ?? -1;
        const stalled = at > 0 && at === last;
        last = at;
        return stalled;
      },
      { message: 'the element should run dry on what it was given', intervals: [300], timeout: T.nav },
    )
    .toBe(true);
  await expect(app.player.deckToggle()).toHaveAccessibleName(/Pause/i);
  await app.player.pause();
  const stoodAt = (await traffic.position(pid)) ?? 0;
  expect(stoodAt, 'the listener should stand far enough in that a start over shows').toBeGreaterThan(1);

  // A token's expiry is whole seconds from its mint, so a mint inside the
  // second of the first would hand back the very token that lapsed; a
  // token the server really let lapse is minutes older than that.
  const minted = traffic.mints(pid)[0]?.answeredAt ?? Date.now();
  await expect
    .poll(() => Date.now(), { message: 'the clock should pass the first mint\'s second' })
    .toBeGreaterThanOrEqual((Math.floor(minted / 1000) + 1) * 1000);

  // The token lapses meanwhile, so the fetch the play needs is refused -
  // that token's, and nobody else's.
  const pressed = traffic.mark();
  await app.player.play();
  stream.refuse(401, LAPSED);
  const refused = traffic.mark();

  // The element fetches a stream minted again, under a token of its own...
  await expect
    .poll(
      () => traffic.fetches(pid).find((f) => f.seq > refused && f.by === 'element')?.token ?? '',
      { message: 'the element should fetch the re-minted stream' },
    )
    .not.toBe('');
  const refetched = traffic.fetches(pid).find((f) => f.seq > refused && f.by === 'element')!;
  expect(refetched.token, 'the stream it fetched should carry a fresh token').not.toBe(
    stream.token,
  );

  // ...and plays on from where the listener stood.
  await expect(app.player.toggle()).toHaveAccessibleName(/Pause/i);
  await expectResumed(traffic, pid, refetched.url, stoodAt);

  // Exactly one mint on the way: counted once the stream minted again has
  // played out, so a second one could not still be coming.
  await expect
    .poll(async () => (await traffic.played(pid, refetched.url))?.to ?? 0, {
      message: 'the stream minted again should play out',
      timeout: T.nav,
    })
    .toBeGreaterThan(9.5);
  expect(traffic.mints(pid).filter((m) => m.seq > pressed)).toHaveLength(1);
});

test('a play after the browser clock passed the token lifetime mints again before touching the media', async ({
  app,
}) => {
  // The browser's clock, faked from before the app boots, so the time
  // the player reads is the time this test sets. The server's clock is
  // untouched: every token it minted stays good throughout.
  await app.page.clock.install();
  const traffic = await MediaTraffic.watch(app.page);
  const { pid } = await app.seed.item(LONG);
  await app.seed.setPosition(pid, 0);
  // Held mid-fetch, so the pause lands on it with play left to hear, and
  // it cannot run out or hand the queue on meanwhile. Paused a second in,
  // so that where it resumes tells a resume from a start over.
  await traffic.holdContinuation(pid);
  await app.music.playAlbumOf(pid);
  await expect
    .poll(async () => (await traffic.position(pid)) ?? 0, { message: 'it should play a second in' })
    .toBeGreaterThanOrEqual(1);
  await app.player.pause();

  const minted = traffic.mints(pid).at(-1);
  expect(minted?.expiresAt, 'the mint should say when its token lapses').toBeTruthy();
  const paused = traffic.fetches(pid).find((f) => f.by === 'element')!.token;
  const stoodAt = (await traffic.position(pid)) ?? 0;

  // A token's expiry is whole seconds from its mint, so a mint inside the
  // second of the first would hand back the same token; the stack's clock
  // is this machine's, which the browser's fake leaves alone.
  const answered = minted!.answeredAt ?? Date.now();
  await expect
    .poll(() => Date.now(), { message: 'the clock should pass the first mint\'s second' })
    .toBeGreaterThanOrEqual((Math.floor(answered / 1000) + 1) * 1000);

  // Inside the player's one-minute margin and short of the lapse itself,
  // by the browser's clock alone.
  await app.page.clock.setSystemTime(Date.parse(minted!.expiresAt!) - 30_000);
  const pressed = traffic.mark();
  await app.player.play();

  // A new mint, asked for before any stream fetch was refused.
  await expect
    .poll(() => traffic.mints(pid).some((m) => m.seq > pressed), {
      message: 'the play should mint the stream again',
    })
    .toBe(true);
  const again = traffic.mints(pid).find((m) => m.seq > pressed)!;
  expect(
    traffic.fetches().filter((f) => f.seq > pressed && f.seq < again.seq),
    'nothing should be fetched under the spent token first',
  ).toEqual([]);
  expect(
    traffic.refusals().filter((r) => r.seq > pressed && r.seq < again.seq),
    'no stream fetch should be refused before the new mint',
  ).toEqual([]);

  // ...and the stream the element goes on with is the one minted again.
  await expect
    .poll(
      () => traffic.fetches(pid).find((f) => f.seq > again.seq && f.by === 'element')?.token ?? '',
      { message: 'the element should fetch the stream minted again' },
    )
    .not.toBe('');
  const refetched = traffic.fetches(pid).find((f) => f.seq > again.seq && f.by === 'element')!;
  expect(refetched.token, 'under a token of its own').not.toBe(paused);

  await expect(app.player.toggle()).toHaveAccessibleName(/Pause/i);
  await expectResumed(traffic, pid, refetched.url, stoodAt);
});

test('a stream the server refuses stands the queue on its track and never skips', async ({
  app,
  page,
}) => {
  const traffic = await MediaTraffic.watch(app.page);
  const { pid: alpha } = await app.seed.item('Alpha Song');
  const { pid: bravo } = await app.seed.item('Bravo Song');
  await app.seed.setPosition(alpha, 0);

  // Alpha is held mid-fetch so it cannot run out on its own: the queue
  // moves when Next moves it. Bravo, the next track, is refused the way a
  // streaming engine that is away refuses it, probe included.
  const held = await traffic.holdContinuation(alpha);
  const restore = await traffic.refuse(bravo, 502, ENGINE_AWAY);
  await app.music.playAlbumOf(alpha);
  await expect
    .poll(() => held() !== undefined, { message: 'Alpha should load and wait on its stream' })
    .toBe(true);

  const next = traffic.mark();
  await clickUntilRequested(page, app.player.deckNext(), (req) =>
    req.url().includes(`/items/${bravo}/play-info`),
  );

  // The start fails out loud, with its retry, and on Bravo.
  await expect(app.player.startRetry()).toBeVisible();
  await expect(app.player.text("Couldn't start Bravo Song")).toBeVisible();
  await expect(app.queue.deckBar()).toHaveAccessibleName(/Bravo Song/);
  // And nothing walked the queue: no skip said, nothing after Bravo
  // minted or fetched.
  await expect(app.player.text(/Skipped/)).toHaveCount(0);
  expect(traffic.mints().filter((m) => m.seq > next && m.pid !== bravo)).toEqual([]);
  expect(traffic.fetches().filter((f) => f.seq > next && f.pid !== bravo)).toEqual([]);

  // The engine is back; the toast's Retry starts Bravo, and it plays.
  restore();
  const retried = traffic.mark();
  await clickUntilRequested(page, app.player.startRetry(), (req) =>
    req.url().includes(`/items/${bravo}/play-info`),
  );
  await expect(app.player.deckToggle()).toHaveAccessibleName(/Pause/i);
  await expect
    .poll(() => traffic.furthest(bravo), { message: 'Bravo should play once the engine is back' })
    .toBeGreaterThan(0.25);
  expect(traffic.refusals().filter((r) => r.seq > retried)).toEqual([]);
});
