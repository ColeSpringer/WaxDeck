import { test, expect } from './fixtures';
import { T } from './driver';
import { MediaTraffic } from './support/media';

// A stream the server re-encodes - a bitrate cap over a lossless original
// - answers no ranges, so the web player seeks it only inside what has
// arrived and mints it again, cut at the target, for anywhere past that.
// The server's half (the cut, and where it says the served audio begins)
// is pinned through the API in playback.spec.ts; this is the client's, in
// the browser whose element decides what has arrived.

/// The long fixture: ten seconds of lossless audio on an album of its own.
const LONG = 'Long Division';

/// How much of the encode has arrived when the listener scrubs: the first
/// two and a half seconds, near enough, with the rest still to come.
const ARRIVED = 0.25;

test('a capped stream seeked past what it has buffered plays on from the target', async ({ app }) => {
  const traffic = await MediaTraffic.watch(app.page);
  const { pid } = await app.seed.item(LONG);
  // From the top, whatever a run before left behind.
  await app.seed.setPosition(pid, 0);

  // The lowest quality on this device, which caps the lossless original.
  await app.nav.enter('settings');
  await app.settings.findAndOpen('bitrate', 'stream-quality-wifi', 'stream-quality-wifi');
  await app.settings.choose('stream-quality-wifi', app.settings.option('stream-quality-wifi', 'low'));

  // Played while the encode is still arriving, as it does to a listener
  // who chose the cap for a slow link.
  await app.music.openAlbumOf(pid);
  await traffic.holdEncode(pid, ARRIVED);
  await app.music.playEntity('play');
  await app.player.ready();
  await expect(app.player.toggle()).toHaveAccessibleName(/Pause/i, { timeout: T.nav });
  await expect
    .poll(() => traffic.mints(pid)[0]?.seekable, { message: 'the cap should make a stream with no ranges' })
    .toBe(false);

  // Scrubbed most of the way along, well past what has arrived: the
  // player seeks inside a stream like this up to two seconds past what it
  // holds, and reopens it for anything further. Half a second past a whole
  // one, where the server cuts, so a cut played from its head shows.
  const fraction = 0.85;
  const lengthSeconds = 10;
  const held = (await traffic.buffered(pid)) ?? 0;
  expect(held, 'the stream should hold well short of the target').toBeLessThan(
    fraction * lengthSeconds - 2,
  );
  const before = traffic.mark();
  const cutAsked = () =>
    traffic.mints(pid).some((m) => m.seq > before && m.positionMs !== undefined);
  await app.player.seekTo(fraction, cutAsked);
  const cut = traffic.mints(pid).find((m) => m.seq > before && m.positionMs !== undefined)!;

  // The player asked for the stream cut at the target, and the server cut
  // it there: the served audio begins on the whole second at or before it.
  const target = cut.positionMs! / 1000;
  expect(target, 'the cut should be asked for where the bar was pressed').toBeGreaterThan(
    fraction * lengthSeconds - 0.5,
  );
  expect(target, 'the cut should be asked for where the bar was pressed').toBeLessThan(
    fraction * lengthSeconds + 0.5,
  );
  await expect
    .poll(() => cut.url ?? '', { message: 'the cut should be minted' })
    .not.toBe('');
  expect(cut.startOffsetMs, 'the server should say where the cut begins').toBe(
    Math.floor(target) * 1000,
  );
  const offset = cut.startOffsetMs! / 1000;

  // And the element plays the cut on from the target: on the item's own
  // clock it begins there, not at the head of the cut, and moves past it.
  await expect(app.player.toggle()).toHaveAccessibleName(/Pause/i);
  await expect
    .poll(async () => offset + ((await traffic.played(pid, cut.url))?.to ?? 0), {
      message: 'the cut should play on from the target',
    })
    .toBeGreaterThan(target + 0.25);
  const span = (await traffic.played(pid, cut.url))!;
  expect(offset + span.from, 'the cut should begin playing at the target').toBeGreaterThan(
    target - 0.25,
  );
  expect(offset + span.from, 'the cut should begin playing at the target').toBeLessThan(
    target + 0.5,
  );
});
