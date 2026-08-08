import { test, expect } from './fixtures';
import * as path from 'node:path';
import { J, T } from './driver';

// The manual-upload journey: pick files in the web UI, group them as
// one album through the upload batch, watch the batch finalize into a
// single review entry, accept it, and find the titles in the library.
// The source files live in .run/upload-src - outside the scanned
// roots, so they only ever enter the library through this pipeline.

const uploadSrc = (name: string) =>
  path.join(__dirname, '..', '.run', 'upload-src', name);

const LANTERNS = ['lantern-one.mp3', 'lantern-two.mp3'];

test('two picked files group as one album and import through review', async ({ app }) => {
  test.setTimeout(J.journey);

  // The batches this account already has. An upload row is kept for a
  // week and the account outlives the run, so a stack this test has used
  // before carries a staged pair per earlier run - and "exactly two of
  // these files are staged" would then be counting all of them. What is
  // this run's is the batch that was not here a moment ago.
  const uploads = async () =>
    (await app.api.get('/uploads', { query: { limit: 100 } })).uploads ?? [];
  const before = new Set((await uploads()).map((r) => r.batchId));

  await app.nav.enter('home');

  // Open the add sheet, choose the file upload, and declare the pair one
  // album.
  await app.uploads.pickFiles(LANTERNS.map(uploadSrc));
  await app.uploads.groupAs('album');

  // Both members stage under one batch and the finalize opens exactly
  // one review entry across them.
  let entryId = '';
  await expect(async () => {
    const fresh = (await uploads()).filter(
      (r) => r.batchId !== undefined && !before.has(r.batchId),
    );
    const batchId = fresh[0]?.batchId;
    expect(batchId, 'the picked pair should stage under a batch of its own').toBeTruthy();
    const members = fresh.filter((r) => r.batchId === batchId && r.state === 'staged');
    expect(members).toHaveLength(2);
    expect(members.map((r) => r.fileName).sort()).toEqual([...LANTERNS].sort());
    expect(members[0].reviewEntryId, 'finalize linked the entry').toBeTruthy();
    expect(members[1].reviewEntryId).toBe(members[0].reviewEntryId);
    entryId = members[0].reviewEntryId!;
  }).toPass({ timeout: T.fetch });

  // The uploads screen shows the quota header and the batch group.
  await app.nav.to('uploads');
  await expect(app.uploads.quota()).toBeVisible();

  // The entry settles (matching is off) and holds both tracks.
  await expect
    .poll(
      async () => {
        const entry = await app.api.tryGet('/review/queue/{entryId}', {
          path: { entryId },
        });
        if (entry === undefined) return 'missing';
        return entry.identifying ? 'identifying' : entry.status;
      },
      { timeout: T.fetch, message: 'the album entry should settle to pending' },
    )
    .toBe('pending');
  const entry = await app.api.get('/review/queue/{entryId}', { path: { entryId } });
  expect(entry.trackCount).toBe(2);

  // Accept as-is: the staged files enter the library.
  await app.api.post('/review/queue/{entryId}/decide', {
    path: { entryId },
    data: { action: 'as-is' },
  });

  // A rescan is a catalog mutation, so a sibling worker may be holding
  // the lease. Presence, never absence: the catalog is shared and a
  // reused stack carries every earlier run's uploads.
  const rescan = await app.api.raw.post('/library/rescan');
  expect([202, 409]).toContain(rescan.status());
  await expect
    .poll(
      async () => {
        const page = await app.api.tryGet('/library/items', {
          query: { mediaType: 'music', limit: 500 },
        });
        const titles = (page?.items ?? []).map((i) => i.title);
        return ['Paper Lanterns', 'River Static'].filter((t) => titles.includes(t));
      },
      { timeout: T.fetch, message: 'the uploaded album should reach the library' },
    )
    .toEqual(['Paper Lanterns', 'River Static']);
});

test('a dropped file uploads through the drag-and-drop area', async ({ app }) => {
  test.setTimeout(J.long);

  // Solo sessions only, and counted as a delta: the picker journey
  // uploads the same fixture as a batch member, and a run against a
  // stack this test has already used carries its own earlier drops.
  const soloRows = async () =>
    ((await app.api.get('/uploads', { query: { limit: 100 } })).uploads ?? []).filter(
      (r) => r.fileName === 'lantern-two.mp3' && !r.batchId,
    );
  const before = (await soloRows()).length;

  await app.nav.enter('home');
  await app.uploads.dropFile(uploadSrc('lantern-two.mp3'));

  // One file: the dialog asks only the media type.
  await app.uploads.confirmMedia();

  // The solo session stages with its own review entry, no batch.
  await expect(async () => {
    const rows = await soloRows();
    expect(rows.length).toBe(before + 1);
    const fresh = rows[0];
    expect(fresh.state).toBe('staged');
    expect(fresh.reviewEntryId).toBeTruthy();
  }).toPass({ timeout: T.fetch });
});

test('accounts without upload rights see no upload affordances', async ({
  otherAccount,
  device,
}) => {
  // A plain account, no upload grant - which is the server's own
  // default, so this is the minted account as it comes.
  const viewer = await device({ as: await otherAccount('viewer') });

  // Home, because that is the one screen the add control renders on. It
  // was asserted from settings, where the control does not exist for
  // anybody - so the assertion held whether or not the upload right
  // gated it, which is the opposite of what it is for. The chrome is up
  // either way, so the two nav assertions below still mean what they
  // meant.
  await viewer.nav.enter('home');

  // No add button, and no way into uploads.
  await expect(viewer.uploads.add()).toHaveCount(0);
  await expect(viewer.shell.navGroup('curation')).toHaveCount(0);
  await expect(viewer.shell.destination('uploads')).toHaveCount(0);
});

test('an upload that declines identification goes straight in', async ({ app }) => {
  test.setTimeout(J.long);

  // Counted as a delta: the stack is shared and outlives the run.
  const soloRows = async () =>
    ((await app.api.get('/uploads', { query: { limit: 100 } })).uploads ?? []).filter(
      (r) => r.fileName === 'lantern-two.mp3' && !r.batchId,
    );
  const before = new Set((await soloRows()).map((r) => r.id));

  await app.nav.enter('home');
  // lantern-two, which nothing here imports: a second copy of an
  // imported track collides on destination by design.
  await app.uploads.pickFiles([uploadSrc('lantern-two.mp3')]);
  await app.uploads.confirmWithoutIdentifying();

  let entryId = '';
  let uploadId = '';
  await expect(async () => {
    const fresh = (await soloRows()).filter((r) => !before.has(r.id));
    expect(fresh, 'the picked file should stage as a session of its own').toHaveLength(1);
    expect(fresh[0].reviewEntryId, 'completing the session opened an entry').toBeTruthy();
    entryId = fresh[0].reviewEntryId!;
    uploadId = fresh[0].id;
  }).toPass({ timeout: T.fetch });

  // Nothing searched and nothing asked: the entry is written filed.
  // Polled: the entry id is committed before the import runs.
  await expect
    .poll(
      async () =>
        (await app.api.get('/review/queue/{entryId}', { path: { entryId } })).status,
      { timeout: T.fetch, message: 'declining imports rather than queueing' },
    )
    .toBe('as-is');
  const entry = await app.api.get('/review/queue/{entryId}', { path: { entryId } });
  expect(entry.identifying, 'a declined entry never enters the match queue').toBe(false);
  expect(entry.identifyDeclined).toBe(true);
  expect(entry.candidates).toHaveLength(0);

  // And the session settles, so its bytes stop counting against the
  // pending-upload quota.
  await expect
    .poll(async () => (await soloRows()).find((r) => r.id === uploadId)?.state, {
      timeout: T.fetch,
      message: 'the session should settle imported',
    })
    .toBe('imported');

  // It is out of the working queue, which is the whole point.
  await app.nav.to('review');
  await expect(app.review.row(entryId)).toHaveCount(0);
});
