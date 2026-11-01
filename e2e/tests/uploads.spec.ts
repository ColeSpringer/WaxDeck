import { test, expect } from './fixtures';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { J, T, retryCatalogBusy } from './driver';
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

  // The batches this account already has: what is this run's is the one
  // that was not here a moment ago and holds these files.
  const before = await app.uploads.batchIds();

  await app.nav.enter('home');

  // Open the add sheet, choose the file upload, and declare the pair one
  // album.
  await app.uploads.pickFiles(LANTERNS.map(uploadSrc));
  await app.uploads.groupAs('album');

  // Both members stage under one batch and the finalize opens exactly
  // one review entry across them.
  const entryId = await app.uploads.stagedEntry(LANTERNS, before);

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

  // Accept as-is: the staged files enter the library, once no sibling
  // worker's rescan or delete holds the catalog's files.
  await retryCatalogBusy(() =>
    app.api.post('/review/queue/{entryId}/decide', {
      path: { entryId },
      data: { action: 'as-is' },
    }),
  );

  // Presence, never absence: the catalog is shared and a reused stack
  // carries every earlier run's uploads.
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

test('a running upload never offers Retry through a list refresh', async ({ app }) => {
  test.setTimeout(J.long);
  const page = app.page;
  await app.nav.enter('uploads');

  // The session this run creates, from the create's own answer, and the
  // first list read that holds it: a page holding a session whose source
  // this client retains is what used to draw the failed face.
  let uploadId = '';
  let createdAs!: (id: string) => void;
  const created = new Promise<string>((resolve) => (createdAs = resolve));
  let listedAfterCreate!: () => void;
  const listed = new Promise<void>((resolve) => (listedAfterCreate = resolve));
  page.on('response', async (response) => {
    const url = new URL(response.url());
    const method = response.request().method();
    try {
      if (method === 'POST' && url.pathname.endsWith('/uploads') && response.ok()) {
        uploadId = ((await response.json()) as { id: string }).id;
        createdAs(uploadId);
      } else if (method === 'GET' && url.pathname.endsWith('/uploads') && response.ok()) {
        const [id, body] = await Promise.all([
          created,
          response.json() as Promise<{ uploads?: { id: string }[] }>,
        ]);
        if (body.uploads?.some((u) => u.id === id)) listedAfterCreate();
      }
    } catch {
      // A body the page has already let go of is not this read.
    }
  });

  // The injected stall: the second chunk waits until the list has been
  // read again holding the session (the server's event for the create
  // refreshes it), and then until this test lets it go. Every chunk
  // after the first is held: a chunk held past the client's timeout is
  // sent again, and that one must not slip through either.
  let release!: () => void;
  const released = new Promise<void>((resolve) => (release = resolve));
  let holding!: () => void;
  const held = new Promise<void>((resolve) => (holding = resolve));
  let puts = 0;
  await page.route('**/uploads/*/data*', async (route) => {
    if (route.request().method() === 'PUT' && ++puts >= 2) {
      if (puts === 2) {
        await listed;
        holding();
      }
      await released;
    }
    try {
      await route.fallback();
    } catch {
      // The client gave up on this chunk while it was held.
    }
  });

  try {
    // Over one chunk, so there is a second to hold.
    await app.uploads.pickOnScreen([uploadSrc('long-take.wav')]);
    await app.uploads.confirmMedia();
    await held;

    await app.uploads.revealPhase(uploadId);
    // A few frames for the refreshed list to draw: Retry is what it drew
    // before.
    await page.evaluate(
      () =>
        new Promise<void>((resolve) => {
          let left = 5;
          const tick = () => (--left === 0 ? resolve() : requestAnimationFrame(tick));
          requestAnimationFrame(tick);
        }),
    );
    await app.uploads.revealPhase(uploadId);
    expect(await app.uploads.retryCountInView(uploadId), 'a running upload offers Retry').toBe(0);

    release();
    await expect
      .poll(
        async () =>
          (await app.api.get('/uploads/{uploadId}', { path: { uploadId } })).state,
        { timeout: T.fetch, message: 'the held upload should finish and stage' },
      )
      .toBe('staged');
    await app.uploads.revealPhase(uploadId);
    expect(await app.uploads.retryCountInView(uploadId), 'a staged upload offers Retry').toBe(0);
  } finally {
    // Staged bytes count against the account's allowance until
    // discarded, and a failed run must not leave a session behind:
    // deleted before a held chunk goes, so nothing can seal it after.
    if (uploadId !== '') {
      await app.api.raw.delete('/uploads/{uploadId}', { path: { uploadId } });
    }
    release();
  }
});

test('the dialog that asks what a file is offers music and audiobook only', async ({
  app,
}) => {
  test.setTimeout(J.long);
  await app.nav.enter('home');
  // One file, so the dialog asks only the media type. Nothing is sent
  // until it is confirmed, and this test never confirms.
  await app.uploads.pickFiles([uploadSrc('lantern-one.mp3')]);
  await app.uploads.openMediaType();

  await expect(app.uploads.mediaTypeOption('music')).toBeVisible();
  await expect(app.uploads.mediaTypeOption('audiobook')).toBeVisible();
  // Podcasts are added by subscribing to a feed.
  await expect(app.uploads.mediaTypeOption('podcast')).toHaveCount(0);
});

test('the server refuses a podcast on every door an upload enters by', async ({ app }) => {
  // The typed client cannot say `podcast` any more, which is the point;
  // a client written before that still can.
  const refused = async (
    door: string,
    response: { status(): number; json(): Promise<unknown> },
  ) => {
    expect(response.status(), `${door} refuses a podcast`).toBe(400);
    expect(await response.json()).toMatchObject({
      code: 'invalid-request',
      message: 'podcasts are added by subscribing to a feed',
    });
  };
  await refused(
    'a session',
    await app.api.raw.post('/uploads', {
      data: { fileName: 'episode.mp3', sizeBytes: 1024, mediaType: 'podcast' } as never,
    }),
  );
  await refused(
    'a batch',
    await app.api.raw.post('/uploads/batches', {
      data: { grouping: 'tracks', mediaType: 'podcast' } as never,
    }),
  );
  await refused(
    'an acquisition',
    await app.api.raw.post('/acquisitions', {
      data: { url: 'https://tube.example/watch?v=one', mediaType: 'podcast' } as never,
    }),
  );
});

test('health reports the format sets and rescan takes the repair pass', async ({
  app,
}) => {
  // The sets the pickers filter with come from the health payload -
  // the effective accepted set (this stack runs the default) and the
  // DRM deny-list, both sorted.
  const health = await app.api.get('/health');
  expect(health.uploadFormats).toContain('flac');
  expect(health.uploadFormats).toEqual([...health.uploadFormats!].sort());
  expect(health.rejectedFormats).toEqual(['aax', 'aaxc']);

  // The forced rescan is a body on the same verb. On the shared server
  // a sibling worker may hold the catalog lease (409, nothing started);
  // a started scan is waited to done, because a forced re-read holds
  // the lease for the whole library and a fire-and-forget window would
  // fail sibling workers' imports instead of this test. The ALAC-heal
  // effect itself is pinned server-side.
  const forced = await app.api.raw.post('/library/rescan', {
    data: { force: true },
  });
  expect([202, 409]).toContain(forced.status());
  if (forced.status() === 202) {
    const job = (await forced.json()) as { pid: string };
    await expect
      .poll(
        async () =>
          (await app.api.get('/jobs/{pid}', { path: { pid: job.pid } })).state,
        { timeout: T.fetch, message: 'the forced scan should run to done' },
      )
      .toBe('done');
  }
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
  const before = await app.uploads.batchIds();

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

  // Two, not four: the folder holds a text file and an Audible container
  // the dialog could not filter out, so the picker's own filtering is
  // what left them behind.
  await app.uploads.stagedEntry(HARBOUR, before);
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

test('a second account re-uploading a library file adds a copy and gains nothing', async ({
  app,
  otherAccount,
  device,
}) => {
  test.setTimeout(J.long);
  // The demo library's alpha, scanned at the stack's start.
  const items = await app.api.get('/library/items', { query: { mediaType: 'music', limit: 500 } });
  const alpha = (items.items ?? []).find((i) => i.title === 'Alpha Song');
  expect(alpha, 'the demo track should be in the library').toBeTruthy();
  const pid = alpha!.pid;
  const filesBefore = new Set(
    (await app.api.get('/items/{pid}/files', { path: { pid } })).files.map((f) => f.filePid),
  );

  // A plain account given the upload right.
  const second = await otherAccount('copier');
  const secondApi = app.api.as(second.token);
  const me = await secondApi.get('/auth/session');
  await app.api.patch('/users/{userId}', { path: { userId: me.user!.id }, data: { uploadEnabled: true } });

  const bytes = fs.readFileSync(path.join(__dirname, '..', '.run', 'library', 'alpha.flac'));
  const up = await secondApi.post('/uploads', {
    data: { fileName: 'alpha-again.flac', sizeBytes: bytes.length, mediaType: 'music' },
  });
  const put = await secondApi.raw.put('/uploads/{uploadId}/data', {
    path: { uploadId: up.id },
    query: { offset: 0 },
    headers: { 'content-type': 'application/octet-stream' },
    data: bytes as never,
  });
  expect(put.ok(), 'the bytes should land').toBeTruthy();
  const done = await secondApi.post('/uploads/{uploadId}/complete', { path: { uploadId: up.id } });
  expect(done.duplicate?.kind, 'completion flags the audio the library holds').toBe('content');
  const entryId = done.reviewEntryId!;
  await expect
    .poll(
      async () => {
        const entry = await secondApi.tryGet('/review/queue/{entryId}', { path: { entryId } });
        if (entry === undefined) return 'missing';
        return entry.identifying ? 'identifying' : entry.status;
      },
      { timeout: T.fetch, message: 'the entry should wait for its uploader' },
    )
    .toBe('pending');

  try {
    // The pane says so, and its as-is is the copy. A sibling worker's
    // forced rescan holds the catalog lease for its whole re-read, and a
    // decide meanwhile answers catalog-busy with the pane left as it
    // was, so the press is made again while the entry still waits: five
    // seconds apart, past the four the refusal's bar stays up over the
    // buttons. The entry, not a press's answer, says when it landed: a
    // press the canvas swallowed sends nothing, and one sent while
    // another runs is told it is being decided.
    const copier = await device({ as: second });
    await copier.nav.to('review');
    await copier.review.open(entryId);
    await expect(copier.review.duplicate()).toBeVisible();
    await expect
      .poll(
        async () => {
          const entry = await secondApi.tryGet('/review/queue/{entryId}', { path: { entryId } });
          if (entry?.status !== 'pending') return entry?.status ?? 'missing';
          await copier.review.decideAsCopy().catch(() => {});
          return 'pending';
        },
        {
          timeout: T.analyze,
          intervals: [5_000],
          message: 'the copy should land once the catalog is free',
        },
      )
      .toBe('as-is');

    // The item kept its details, holds one more file, and is not the
    // uploader's to edit.
    const item = await app.api.get('/items/{pid}', { path: { pid } });
    expect(item.title).toBe('Alpha Song');
    const files = (await app.api.get('/items/{pid}/files', { path: { pid } })).files;
    const added = files.filter((f) => !filesBefore.has(f.filePid));
    expect(added.map((f) => f.role)).toEqual(['alternate']);
    const perms = await secondApi.get('/items/{pid}/permissions', { path: { pid } });
    expect(perms.mayCurate).toBe(false);
  } finally {
    // The stack is shared: whatever the run added goes again, or a kept
    // stack holds the next run's upload where it already sits.
    const files = (await app.api.get('/items/{pid}/files', { path: { pid } })).files;
    const added = files.filter((f) => !filesBefore.has(f.filePid)).map((f) => f.filePid);
    if (added.length > 0) {
      await retryCatalogBusy(() =>
        app.api.post('/items/{pid}/files/delete', {
          path: { pid },
          data: { filePids: added, mode: 'permanent', dryRun: false },
        }),
      );
    }
  }
});

test('an MP3 uploaded as an audiobook stays a book through a forced rescan', async ({ app }) => {
  test.setTimeout(J.long);
  const part = uploadSrc(path.join('Mira Loom', 'The Loose Chapters', '01 - Chapter One.mp3'));
  const bytes = fs.readFileSync(part);
  const up = await app.api.post('/uploads', {
    data: { fileName: '01 - Chapter One.mp3', sizeBytes: bytes.length, mediaType: 'audiobook' },
  });
  const put = await app.api.raw.put('/uploads/{uploadId}/data', {
    path: { uploadId: up.id },
    query: { offset: 0 },
    headers: { 'content-type': 'application/octet-stream' },
    data: bytes as never,
  });
  expect(put.ok(), 'the bytes should land').toBeTruthy();
  const done = await app.api.post('/uploads/{uploadId}/complete', { path: { uploadId: up.id } });
  // A stack that kept an earlier run's book holds this copy where that
  // one sits and adds nothing; completion names the book it repeats.
  const earlier = done.duplicate?.kind === 'content' ? (done.duplicate.itemPid ?? '') : '';
  const entryId = done.reviewEntryId!;
  let pid = '';
  try {
    await expect
      .poll(
        async () => {
          const entry = await app.api.tryGet('/review/queue/{entryId}', { path: { entryId } });
          if (entry === undefined) return 'missing';
          return entry.identifying ? 'identifying' : entry.status;
        },
        { timeout: T.fetch, message: 'the entry should settle to pending' },
      )
      .toBe('pending');
    await retryCatalogBusy(() =>
      app.api.post('/review/queue/{entryId}/decide', { path: { entryId }, data: { action: 'as-is' } }),
    );
    // The import fills the track's pid once it resolves.
    await expect
      .poll(
        async () => {
          const entry = await app.api.tryGet('/review/queue/{entryId}', { path: { entryId } });
          pid = entry?.tracks[0]?.pid ?? earlier;
          return pid;
        },
        { timeout: T.fetch, message: 'the part should enter the library' },
      )
      .toMatch(/^bk-/);

    // A forced rescan reads every file again; the import's pinned kind
    // holds through it. A sibling worker may hold the catalog lease, so
    // a refusal is asked again.
    let jobPid = '';
    await expect
      .poll(
        async () => {
          const resp = await app.api.raw.post('/library/rescan', { data: { force: true } });
          if (resp.status() === 202) jobPid = ((await resp.json()) as { pid: string }).pid;
          return resp.status();
        },
        { timeout: T.analyze, message: 'a forced rescan should start' },
      )
      .toBe(202);
    await expect
      .poll(async () => (await app.api.get('/jobs/{pid}', { path: { pid: jobPid } })).state, {
        timeout: T.analyze,
        message: 'the forced rescan should run to done',
      })
      .toBe('done');
    const book = await app.api.raw.get('/books/{pid}', { path: { pid } });
    expect(book.status(), 'the book keeps its pid').toBe(200);
  } finally {
    // The stack is shared: the book goes again, or the next run's upload
    // finds it where its copy would go.
    if (pid.startsWith('bk-')) {
      await retryCatalogBusy(() =>
        app.api.post('/library/items/delete', { data: { pids: [pid], mode: 'permanent', dryRun: false } }),
      );
    }
  }
});

test('a picked book folder uploads as one book in parts', async ({ app }) => {
  test.setTimeout(J.journey);
  // The book is this test's own: the single-part journey uploads the
  // loose book's first part, which would be a copy of this folder's.
  const TITLE = 'The Folded Letters';
  const PARTS = ['01 - First Letter.mp3', '02 - Second Letter.mp3'];
  const before = await app.uploads.batchIds();
  const books = async () =>
    (await app.api.get('/library/items', { query: { mediaType: 'audiobook', limit: 500 } })).items.filter(
      (i) => i.title === TITLE,
    );
  const earlier = new Set((await books()).map((i) => i.pid));
  let pid = '';

  try {
    // The Books hub knows what the folder is, so the dialog does not ask;
    // the default grouping is one book in parts and is confirmed as is.
    await app.nav.enter('books');
    await app.uploads.pickFolder(uploadSrc(path.join('Tamsin Reed', TITLE)), SemanticsIds.booksAdd);
    await expect(app.uploads.mediaConfirm()).toBeVisible({ timeout: T.nav });
    await expect(app.uploads.control(SemanticsIds.uploadMediaType)).toHaveCount(0);
    await app.uploads.confirmMedia();

    const entryId = await app.uploads.stagedEntry(PARTS, before);

    await expect
      .poll(
        async () => {
          const entry = await app.api.tryGet('/review/queue/{entryId}', { path: { entryId } });
          if (entry === undefined) return 'missing';
          return entry.identifying ? 'identifying' : entry.status;
        },
        { timeout: T.fetch, message: 'the book entry should settle to pending' },
      )
      .toBe('pending');
    await retryCatalogBusy(() =>
      app.api.post('/review/queue/{entryId}/decide', { path: { entryId }, data: { action: 'as-is' } }),
    );

    await expect
      .poll(
        async () => {
          pid = (await books()).find((i) => !earlier.has(i.pid))?.pid ?? '';
          if (pid === '') return 0;
          return (await app.api.get('/books/{pid}', { path: { pid } })).parts.length;
        },
        { timeout: T.fetch, message: 'the folder should become one book of two parts' },
      )
      .toBe(2);
  } finally {
    // The book goes again, as in the single-part journey above.
    if (pid.startsWith('bk-')) {
      await retryCatalogBusy(() =>
        app.api.post('/library/items/delete', { data: { pids: [pid], mode: 'permanent', dryRun: false } }),
      );
    }
  }
});
