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
// here is one every other spec's account sees on the same track for the
// rest of the run. The least-contended fixture track, and the slot put
// back either way: this spec's subject is the setting, not the holding.
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
  } finally {
    // Back to whatever the scan gave it. The lock goes with the artifact,
    // so clearing the slot also clears the hold this put on enrichment.
    await app.api.delete('/items/{pid}/artwork', {
      path: { pid },
      query: { role: 'front' },
    });
  }
});
