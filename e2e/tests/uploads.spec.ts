import { test, expect } from './fixtures';
import * as path from 'node:path';
import { J, T } from './driver';
import { SemanticsIds } from './semantics-ids';

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
  // this run's is the batch that was not here a moment ago and holds
  // these files: the folder journey opens a batch of its own beside this
  // one, so "the newest batch" is somebody else's half the time.
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
      (r) =>
        r.batchId !== undefined &&
        !before.has(r.batchId) &&
        LANTERNS.includes(r.fileName),
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
  await app.nav.enter('uploads');
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

test('a picked folder uploads its audio and leaves the rest', async ({ app }) => {
  test.setTimeout(J.journey);

  // The folder pick is the web's own: browsers have no folder dialog
  // except an <input webkitdirectory>, so this is the one journey that
  // proves the tile is drawn there, that the chooser's answer reaches
  // the upload flow, and that what is not audio is left behind.
  //
  // It does not prove the hierarchy survived. Nothing on the wire
  // carries `batchPath` back - `ReviewTrack.path` is staging-relative -
  // and `auto` clusters on the album tag folded with the disc folder,
  // so these two land in one entry whether the path rode along or was
  // dropped. The half this cannot see is pinned a layer down, where
  // `file_picker_web_test.dart` reads `webkitRelativePath` into
  // `relativeDir` against real browser files.
  //
  // The album is this test's own, or it would race the file journey's
  // for the destination - and the rows are read back by file name for
  // the same reason, since the two batches open side by side.
  const HARBOUR = ['harbour-one.mp3', 'harbour-two.mp3'];
  const uploads = async () =>
    (await app.api.get('/uploads', { query: { limit: 100 } })).uploads ?? [];
  const before = new Set((await uploads()).map((r) => r.batchId));

  await app.nav.enter('home');
  await app.uploads.pickFolder(uploadSrc('Harbour Lights'));
  // Auto-detect, which is what a folder is picked for: the disc
  // subfolder rides along as the clustering hint.
  await app.uploads.groupAs('auto');
  // What the flow says once the dialog is gone (a toast under a modal
  // is hidden from the semantics tree): the identify announcement
  // first, then the DRM report the messenger queued behind it - the
  // memoir.aax was left behind by name, while the text file is shed
  // without commentary. The announcement's sentence lives on its
  // snackbar's group label - the action button folds the row into one
  // node - so its button is what a locator can hold; the DRM toast has
  // no button and its text stands as a node of its own. T.fetch for
  // the first: it appears only after every member uploads and the
  // batch finalizes, the same work the poll below budgets T.fetch for.
  await expect(
    app.uploads.control(SemanticsIds.uploadIdentifyingReview),
  ).toBeVisible({ timeout: T.fetch });
  await expect(app.uploads.text('Skipped 1 Audible file')).toBeVisible({
    timeout: T.assert,
  });

  await expect(async () => {
    const fresh = (await uploads()).filter(
      (r) =>
        r.batchId !== undefined &&
        !before.has(r.batchId) &&
        HARBOUR.includes(r.fileName),
    );
    const batchId = fresh[0]?.batchId;
    expect(batchId, 'the picked folder should stage under a batch of its own').toBeTruthy();
    const members = fresh.filter((r) => r.batchId === batchId && r.state === 'staged');
    // Two, not four: the folder holds a text file and an Audible
    // container the dialog could not filter out, so the picker's own
    // filtering is what left them behind.
    expect(members).toHaveLength(2);
    expect(members.map((r) => r.fileName).sort()).toEqual([...HARBOUR].sort());
    expect(members[0].reviewEntryId, 'finalize linked the entry').toBeTruthy();
    expect(members[1].reviewEntryId).toBe(members[0].reviewEntryId);
  }).toPass({ timeout: T.fetch });
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

  // No add button, and none of the rows an account without the upload
  // right has nothing behind. They were one Curation group to hide
  // before the nav was flattened; each is its own row now, gated on its
  // own predicate - the upload right for uploads' two lists, the role
  // for the console - so each is its own assertion.
  await expect(viewer.uploads.add()).toHaveCount(0);
  await expect(viewer.shell.destination('tasks')).toHaveCount(0);
  await expect(viewer.shell.destination('review')).toHaveCount(0);
  await expect(viewer.shell.destination('admin')).toHaveCount(0);
  // And the console refuses the location rather than drawing panels that
  // all answer 403 - the chrome is not the only gate.
  await viewer.nav.open('/admin', viewer.shell.adminForbidden());
});

test('an upload that declines identification goes straight in', async ({ app }) => {
  test.setTimeout(J.long);

  // Counted as a delta: the stack is shared and outlives the run.
  const soloRows = async () =>
    ((await app.api.get('/uploads', { query: { limit: 100 } })).uploads ?? []).filter(
      (r) => r.fileName === 'sodium-sky.mp3' && !r.batchId,
    );
  const before = new Set((await soloRows()).map((r) => r.id));

  await app.nav.enter('home');
  // The single is this test's own file. Declining imports on arrival,
  // so uploading a lantern would race the album journey for the
  // destination - and a shared fileName would let soloRows alias the
  // drag-and-drop journey's session. The import is once per stack: a
  // rerun against a stack that kept it is flagged as a duplicate and
  // deliberately waits for review instead of importing.
  await app.uploads.pickFiles([uploadSrc('sodium-sky.mp3')]);
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
