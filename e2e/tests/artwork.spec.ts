import { readFileSync } from 'node:fs';
import path from 'node:path';
import { crc32, deflateSync } from 'node:zlib';
import { test, expect } from './fixtures';
import { clickThrough } from './driver/gestures';

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

// Long Division's own front and back make a second picture on its
// full-screen player. Its ten seconds leave a pause at once ample room to
// land, before the player moves on to a track with no pictures. The
// covers are the catalog's alone, and no spec that plays it reads its art.
test('the full-screen artwork turns to the back cover', async ({ app }) => {
  const { pid } = await app.seed.item('Long Division');
  const set: ('front' | 'back')[] = [];
  try {
    for (const role of ['front', 'back'] as const) {
      const put = await app.api.raw.replace('/items/{pid}/artwork', readFileSync(coverSrc), {
        path: { pid },
        query: { role },
      });
      expect(put.status()).toBe(200);
      set.push(role);
    }

    await app.music.playAlbumOf(pid);
    await app.player.pause();
    await expect(app.player.artwork()).toHaveAccessibleName('Artwork 1 of 2');

    await clickThrough(app.player.artwork(), app.player.text('Back cover: Set by hand'));
    await expect(app.player.artwork()).toHaveAccessibleName('Artwork 2 of 2');
  } finally {
    // Unpinned and cleared, the track is as the scan left it. Raw, so a
    // failure above stays the one the run reports.
    if (set.length > 0) {
      await app.api.raw.put('/items/{pid}/locks', {
        path: { pid },
        data: { fields: set.map((role) => (role === 'front' ? 'art' : `art.${role}`)), locked: false },
      });
      for (const role of set) {
        await app.api.raw.delete('/items/{pid}/artwork', { path: { pid }, query: { role } });
      }
    }
  }
});

// A cover set on another device, reaching an index that is already open.
//
// Slow Signal is Long Division's artist and nobody else's, and no spec
// reads that artist's picture; the scan gives it none, so clearing it
// puts it back. The track is the one the test above sets the covers of,
// in parallel: its writes name the track and its album, never the
// artist, and it counts the track's own slots, which an artist's
// picture is not one of. The write is the test's API hand, which is
// another device as far as the page can tell, and this account sees the
// whole catalog, so the server names the artist to it. What the page
// then owes is a request: the artist's art URL, asked for again under a
// tag.
//
// Twice, because the client gets there by two paths that end in that
// same request. Named in a quiet catalog, the cover is dropped as its
// name is heard. Named inside a stretch of changes too busy to follow
// by name, as a scan or the rest of the suite can make one, it is asked
// for with every other cover once the stretch ends. In order, on one
// worker: each sets the same artist's picture, as the test after them
// does.
const ARTIST = 'Slow Signal';

test.describe.serial('a cover set on another device is asked for again, under a new name, by an open artists index', () => {
  for (const busy of [false, true]) {
    test(busy ? 'inside a stretch too busy to follow by name, when it ends' : 'as its artist is named', async ({
      app,
      api,
    }) => {
      const track = await app.seed.item('Long Division');
      const { artistPid } = await app.api.get('/items/{pid}', { path: { pid: track.pid } });
      expect(artistPid, 'Long Division should be credited to an artist').toMatch(/^ar-/);
      const artist = { entityType: 'artist', entityPid: artistPid! } as const;
      const socket = await app.artwork.liveSocket();
      try {
        await app.nav.enter('artists');
        await app.artwork.intoView(app.music.indexRow(ARTIST));
        await socket.subscribed();

        const asked = app.artwork.askedAfresh(artistPid!);
        // With no pause before the write, so its name is heard in the
        // window that ran over.
        const said = busy ? socket.busy() : null;
        const put = await api.raw.replace(
          '/entities/{entityType}/{entityPid}/artwork',
          readFileSync(coverSrc),
          { path: artist, query: { role: 'front' } },
        );
        expect(put.status()).toBe(200);
        const at = await asked;
        if (said !== null) app.artwork.askedAtStretchEnd(said, at);
      } finally {
        // Unpinned, then cleared: the artist as the scan left it. Raw, so a
        // failure above stays the one the run reports.
        await app.api.raw.put('/entities/{entityType}/{entityPid}/artwork/lock', {
          path: artist,
          data: { locked: false },
        });
        await app.api.raw.delete('/entities/{entityType}/{entityPid}/artwork', {
          path: artist,
          query: { role: 'front' },
        });
      }
    });
  }

  // A cover replaced while no page was open, reaching the next one.
  //
  // A page that heard a catalog change keeps where it heard it up to, and
  // presents it when a page of the same browser next subscribes; the
  // server answers with the names of what changed after it. So the first
  // page draws a cover set while it is open (which is what it hears), and
  // closes; the cover is replaced; a new page in the same browser opens
  // the index and asks for the cover under a tag newer than the first
  // page's, and is given the new picture. Without the position presented
  // nothing names the artist, and the browser goes on drawing the copy it
  // keeps for the day. In the group, for the artist it shares.
  test('and by the next one the browser opens, when no page was open as it changed', async ({
    app,
    api,
    tab,
  }) => {
    const track = await app.seed.item('Long Division');
    const { artistPid } = await app.api.get('/items/{pid}', { path: { pid: track.pid } });
    expect(artistPid, 'Long Division should be credited to an artist').toMatch(/^ar-/);
    const artist = { entityType: 'artist', entityPid: artistPid! } as const;
    const setCover = async (bytes: Buffer) => {
      const put = await api.raw.replace('/entities/{entityType}/{entityPid}/artwork', bytes, {
        path: artist,
        query: { role: 'front' },
      });
      expect(put.status()).toBe(200);
    };
    try {
      const socket = await app.artwork.liveSocket();
      await app.nav.enter('artists');
      await app.artwork.intoView(app.music.indexRow(ARTIST));
      await socket.subscribed();
      const drawn = app.artwork.coverAskedAfter(artistPid!, 0);
      await setCover(solidPng([200, 40, 40]));
      const first = await drawn;
      await app.artwork.leave();

      await setCover(readFileSync(coverSrc));
      const back = await tab();
      const told = await back.artwork.liveSocket();
      const asked = back.artwork.coverAskedAfter(artistPid!, first.tag);
      await back.nav.enter('artists');
      // Named in answer to its subscribe: nothing changed after it opened,
      // so no live frame can name the artist, and a tag raised for any
      // other reason does not pass this.
      await told.named(artistPid!);
      await back.artwork.intoView(back.music.indexRow(ARTIST));
      const again = await asked;
      expect(again.body.equals(first.body), 'the returning page was given the picture it had').toBe(false);
    } finally {
      await app.api.raw.put('/entities/{entityType}/{entityPid}/artwork/lock', {
        path: artist,
        data: { locked: false },
      });
      await app.api.raw.delete('/entities/{entityType}/{entityPid}/artwork', {
        path: artist,
        query: { role: 'front' },
      });
    }
  });
});

/// A square PNG of one colour, a cover unlike the TIFF one.
function solidPng([r, g, b]: [number, number, number], size = 64): Buffer {
  const chunk = (type: string, data: Buffer) => {
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const framed = Buffer.alloc(body.length + 8);
    framed.writeUInt32BE(data.length, 0);
    body.copy(framed, 4);
    framed.writeUInt32BE(crc32(body), body.length + 4);
    return framed;
  };
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8; // bits per channel
  header[9] = 2; // truecolour
  const row = Buffer.alloc(1 + 3 * size);
  for (let x = 0; x < size; x++) row.set([r, g, b], 1 + 3 * x);
  const pixels = Buffer.concat(Array.from({ length: size }, () => row));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(pixels)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

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
