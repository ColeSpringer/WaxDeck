import path from 'node:path';
import { test, expect } from './fixtures';

// Setting a cover by hand, in the one format that separates the two
// recognizers.
//
// Go's image sniffing stops at BMP, so a TIFF gets past the artwork
// guard only because the guard asks the catalog's own recognizer
// instead. What the slot reports afterwards proves the rest of the
// chain: the store measured it, the resolver thumbnailed it, and the
// byte endpoint labelled it as itself rather than as jpeg.

// Synthesized by the fixtures module beside the upload sources, since
// this is a file a picker walks to rather than media under scan.
const coverSrc = path.join(__dirname, '..', '.run', 'upload-src', 'sleeve.tiff');

// Artwork is a catalog fact rather than an account's, so a cover set
// here is one every other spec's account sees on the same track until
// the teardown clears it. The least-contended fixture track, no other
// spec asserts its art, and the scan gave it none to restore.
const TRACK = 'Delta Song';

test('a cover the standard library cannot sniff is set, measured, and served as itself', async ({
  app,
}) => {
  const { pid } = await app.seed.item(TRACK);
  try {
    await app.nav.open(app.artwork.editorLocation(pid), app.artwork.slot('front'));

    await app.artwork.setCoverFromFile('front', coverSrc);

    // The tile says what it holds, in the words the app draws.
    await expect(
      app.artwork.slotNamed(/Front cover: tiff, 240 x 180/),
    ).toBeVisible();

    // The same three facts off the read the app draws that line from.
    const roles = await app.api.get('/items/{pid}/art-roles', { path: { pid } });
    expect(roles.roles.find((r) => r.role === 'front')).toMatchObject({
      format: 'tiff',
      width: 240,
      height: 180,
    });

    // The original is served as what it is. Before this it was labelled
    // jpeg, because the mime table fell back to jpeg for everything it
    // did not list.
    const whole = await app.api.raw.get('/items/{pid}/art', { path: { pid } });
    expect(whole.status()).toBe(200);
    expect(whole.headers()['content-type']).toContain('image/tiff');
    // And it is served as a picture and nothing else: these bytes came
    // from a file somebody picked, under a URL a browser can open.
    expect(whole.headers()['x-content-type-options']).toBe('nosniff');

    // A thumbnail is a re-encode rather than the source handed back
    // under a size it never had.
    const thumb = await app.api.raw.get('/items/{pid}/art', {
      path: { pid },
      query: { size: 128 },
    });
    expect(thumb.status()).toBe(200);
    expect(thumb.headers()['content-type']).not.toContain('image/tiff');
    expect((await thumb.body()).length).toBeLessThan((await whole.body()).length);

    // The picture is 240 across, so this box is one it already fits, and
    // "already fits" used to mean the stored bytes came back whole -
    // which handed a browser a TIFF under a request that meant "give me
    // something to draw". A sized resolve now re-encodes a format a
    // client cannot paint, at the source's own size, so the same
    // request answers a picture instead.
    const roomy = await app.api.raw.get('/items/{pid}/art', {
      path: { pid },
      query: { size: 512 },
    });
    expect(roomy.status()).toBe(200);
    expect(roomy.headers()['content-type']).not.toContain('image/tiff');

    // Which leaves omitting the parameter as the one way to ask for the
    // stored bytes - the request that means "the original", where the
    // format is the caller's problem by construction. Naming a size is
    // never that: the endpoint refuses anything under 16, so there is no
    // number that means "unsized".
    const zero = await app.api.raw.get('/items/{pid}/art', {
      path: { pid },
      query: { size: 0 },
    });
    expect(zero.status()).toBe(400);
  } finally {
    // Clears the cover; the pin the set created stays, by ClearItemArtwork
    // design ("there is no cover", not "refill this"). Inert here: the
    // suite runs with matching off, so nothing would refill it anyway.
    await app.api.delete('/items/{pid}/artwork', {
      path: { pid },
      query: { role: 'front' },
    });
  }
});

// The shared podcast feed, the same one podcasts.spec subscribes to. A
// show and its cover are catalog-wide; no other spec asserts the show's
// artwork, and the teardown hands the slot back to the feed.
const FEED_URL = 'http://127.0.0.1:4421/feed.xml';

test('a show cover is set through the show menu, pinned, and handed back', async ({
  app,
}) => {
  // Subscribing (idempotently for this account) is how the show's pid
  // is learned; the artwork account is an admin, who holds the
  // manage-podcasts right implicitly, which is what the menu gates on.
  const showPid = await app.seed.subscribePodcast(FEED_URL);
  try {
    await app.nav.open(app.podcasts.showLocation(showPid), app.podcasts.overflow());

    // The door: Set cover in the show's own menu, opening the artwork
    // manager on the show's entity slots.
    await app.podcasts.openCoverManager(app.artwork.slot('front'));
    await app.artwork.setCoverFromFile('front', coverSrc);
    await expect(app.artwork.slotNamed(/Front cover: tiff/)).toBeVisible();

    // The read the header's caption rides: a hand-set cover reports
    // itself as a person's choice, and the write pinned it - the pin is
    // what keeps the next feed sync from fetching the feed's image over
    // it.
    const roles = await app.api.get('/items/{pid}/art-roles', {
      path: { pid: showPid },
    });
    expect(roles.artSource?.source).toBe('user');
    expect(roles.roles.find((r) => r.role === 'front')?.locked).toBe(true);
  } finally {
    // Unpin, then clear: the two steps that hand the slot back to the
    // feed, whose image refills on the show's next sync. Guarded on a
    // user cover actually standing: the show is shared catalog state,
    // and a run that failed before the set must not strip the feed's
    // own cover - the static e2e feed answers Not-Modified afterwards,
    // which would leave the show coverless for the rest of the run.
    const roles = await app.api.tryGet('/items/{pid}/art-roles', {
      path: { pid: showPid },
    });
    if (roles?.artSource?.source === 'user') {
      await app.api.put('/entities/{entityType}/{entityPid}/artwork/lock', {
        path: { entityType: 'podcast', entityPid: showPid },
        data: { locked: false },
      });
      await app.api.delete('/entities/{entityType}/{entityPid}/artwork', {
        path: { entityType: 'podcast', entityPid: showPid },
        query: { role: 'front' },
      });
    }
  }
});
