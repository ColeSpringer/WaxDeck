import { test, expect } from './fixtures';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { J, T } from './driver';
import type { App } from './driver';
import { clickThrough, clickToward } from './driver/gestures';

// The release workbench journey: import an album of this run's own
// through the upload pipeline, open its workbench, edit one member in
// the pane, bulk-write the pair, and rename the release - which
// regroups its members onto a fresh album pid and takes the workbench
// with them. Everything mutated here entered the library through this
// spec's own account, so no shared fixture is renamed out from under a
// sibling worker.

const uploadSrc = (name: string) =>
  path.join(__dirname, '..', '.run', 'upload-src', name);

/// Upload the meridian pair (this journey's own fixture album - the
/// lantern pair belongs to the manual-upload journey, whose import
/// would find this one already holding the destination) as one album
/// batch and import it as-is,
/// answering the member pids and the album entity they grouped onto.
/// The file names are stamped per run so a reused stack's earlier
/// copies never collide with this run's accounting.
async function importOwnAlbum(
  app: App,
  stamp: string,
): Promise<{ albumPid: string; trackPids: string[] }> {
  const batch = await app.api.post('/uploads/batches', {
    data: { grouping: 'album', mediaType: 'music' },
  });
  for (const src of ['meridian-one.mp3', 'meridian-two.mp3']) {
    const bytes = fs.readFileSync(uploadSrc(src));
    const up = await app.api.post('/uploads', {
      data: {
        fileName: `workbench-${stamp}-${src}`,
        sizeBytes: bytes.length,
        mediaType: 'music',
        batchId: batch.id,
      },
    });
    const put = await app.api.raw.put('/uploads/{uploadId}/data', {
      path: { uploadId: up.id },
      query: { offset: 0 },
      headers: { 'content-type': 'application/octet-stream' },
      // The generated types only model JSON bodies; this endpoint takes
      // raw bytes, which Playwright sends verbatim for a Buffer.
      data: bytes as never,
    });
    expect(put.ok(), 'the chunk should land').toBeTruthy();
    await app.api.post('/uploads/{uploadId}/complete', {
      path: { uploadId: up.id },
    });
  }
  const done = await app.api.post('/uploads/batches/{batchId}/complete', {
    path: { batchId: batch.id },
  });
  const entryId = done.reviewEntryIds?.[0];
  expect(entryId, 'the batch should open one album entry').toBeTruthy();

  await expect
    .poll(
      async () => {
        const entry = await app.api.tryGet('/review/queue/{entryId}', {
          path: { entryId: entryId! },
        });
        if (entry === undefined) return 'missing';
        return entry.identifying ? 'identifying' : entry.status;
      },
      { timeout: T.fetch, message: 'the entry should settle to pending' },
    )
    .toBe('pending');
  await app.api.post('/review/queue/{entryId}/decide', {
    path: { entryId: entryId! },
    data: { action: 'as-is' },
  });

  // The import fills the entry's tracks with their catalog pids.
  let trackPids: string[] = [];
  await expect
    .poll(
      async () => {
        const entry = await app.api.tryGet('/review/queue/{entryId}', {
          path: { entryId: entryId! },
        });
        trackPids = (entry?.tracks ?? [])
          .map((t) => t.pid)
          .filter((p): p is string => p !== undefined);
        return trackPids.length;
      },
      { timeout: T.fetch, message: 'both members should enter the library' },
    )
    .toBe(2);

  let albumPid = '';
  await expect
    .poll(
      async () => {
        const item = await app.api.tryGet('/items/{pid}', {
          path: { pid: trackPids[0] },
        });
        albumPid = item?.albumPid ?? '';
        return albumPid;
      },
      { timeout: T.fetch, message: 'the members should group as a release' },
    )
    .toMatch(/^al-/);
  return { albumPid, trackPids };
}

test('the workbench edits a member, bulk-writes the pair, and follows a regroup', async ({ app, page }) => {
  test.setTimeout(J.journey);
  const stamp = Date.now().toString(36);
  const { albumPid, trackPids } = await importOwnAlbum(app, stamp);

  await app.metadata.openWorkbench(albumPid);
  // The release opens on its own pane: the album entity form.
  await expect(app.metadata.albumEditor()).toBeVisible({ timeout: T.fetch });

  // A member's row swaps its editor into the pane.
  await clickThrough(
    app.metadata.trackRow(trackPids[0]),
    app.metadata.itemField('title'),
  );

  // Check both members and bulk-write a comment through one batch. A
  // long press starts the selection, the same gesture as on touch; the
  // second row joins by tap, and the pane's own heading is the proof
  // both are in.
  await app.metadata.hold(app.metadata.trackRow(trackPids[0]));
  await app.metadata.bulkPane().waitFor({ timeout: T.step });
  // One attempt, not a retried click: a second click would toggle the
  // check back off. The pane's heading proves both members are in.
  await clickToward(app.metadata.trackRow(trackPids[1]), {
    shows: app.metadata.bulkPane().getByText('Edit 2 tracks').first(),
  });
  const comment = `workbench pass ${stamp}`;
  await app.metadata.intoView(
    app.metadata.bulkField('comment'),
    app.metadata.bulkPane(),
  );
  await app.metadata.type(app.metadata.bulkField('comment'), comment);
  // Goal first, then the click: a landed save disables the button, so
  // a retry that leads with the click would wait on a control that is
  // never coming back. The server's own record is the goal.
  const commentLanded = async () =>
    (
      await app.api.tryGet('/items/{pid}/metadata', {
        path: { pid: trackPids[0] },
      })
    )?.fields?.comment === comment;
  await expect(async () => {
    if (await commentLanded()) return;
    await app.metadata.bulkSave().click({ timeout: T.step });
    expect(await commentLanded()).toBe(true);
  }).toPass({ timeout: T.fetch });
  for (const pid of trackPids) {
    await expect
      .poll(
        async () => {
          const metadata = await app.api.tryGet('/items/{pid}/metadata', {
            path: { pid },
          });
          return metadata?.fields?.comment;
        },
        { timeout: T.fetch, message: 'the bulk comment should reach both members' },
      )
      .toBe(comment);
  }

  // The album row leaves the selection and returns the release's own
  // form to the pane, in one move.
  await clickThrough(app.metadata.albumRow(), app.metadata.albumEditor());

  // The pane's fetch previews before it applies: on a server with no
  // injected providers the sheet opens on its empty state, and
  // cancelling it writes nothing. Driven on this spec's own member so
  // no shared fixture is enriched. A taller viewport instead of a
  // wheel: the lyrics box sits mid-pane and swallows wheel events that
  // pass over it, so scrolling to the button under the default height
  // stalls on exactly this editor.
  await clickThrough(
    app.metadata.trackRow(trackPids[1]),
    app.metadata.itemField('title'),
  );
  const view = page.viewportSize();
  await page.setViewportSize({ width: view!.width, height: 2400 });
  await clickThrough(app.metadata.enrichButton(), app.metadata.previewSheet());
  await clickToward(app.metadata.previewCancel(), {
    gone: app.metadata.previewSheet(),
  });
  await page.setViewportSize(view!);

  // The artist behind the release opens its own editor at the same
  // metadata location. Render only: the artist entity is keyed by
  // name, so a save here could cross another worker's assertions. The
  // pid is asserted, not gated on - inside an if this whole block
  // would silently no-op green.
  const member = await app.api.get('/items/{pid}', {
    path: { pid: trackPids[0] },
  });
  expect(member.artistPid, 'an imported member names its artist').toBeTruthy();
  await app.metadata.openEntityEditor(member.artistPid!);
  await app.metadata.itemField('sort').waitFor({ timeout: T.fetch });
  await app.metadata.openWorkbench(albumPid);
  // Back on the release's own form for the rename below, whichever
  // branch ran: a reload lands there, and the row click is one move
  // from the member's editor.
  await clickThrough(app.metadata.albumRow(), app.metadata.albumEditor());

  // Rename the release. The rewrite goes to the member tracks, which
  // regroups them onto a fresh album pid - and the workbench follows.
  const renamed = `Workbench Regroup ${stamp}`;
  await app.metadata.intoView(
    app.metadata.rewriteField('album'),
    app.metadata.pane(),
  );
  await app.metadata.type(app.metadata.rewriteField('album'), renamed);
  await app.metadata.intoView(
    app.metadata.rewriteApply(),
    app.metadata.pane(),
  );
  await clickThrough(app.metadata.rewriteApply(), app.metadata.rewriteConfirm());
  await clickToward(app.metadata.rewriteConfirm(), {
    gone: app.metadata.rewriteConfirm(),
  });

  // The members landed on a new album, and the location moved with
  // them rather than staying on the ghost of the old one.
  let regrouped = '';
  await expect
    .poll(
      async () => {
        const item = await app.api.tryGet('/items/{pid}', {
          path: { pid: trackPids[0] },
        });
        regrouped = item?.albumPid ?? '';
        return regrouped !== '' && regrouped !== albumPid;
      },
      { timeout: T.fetch, message: 'the rewrite should regroup the release' },
    )
    .toBe(true);
  await expect
    .poll(() => app.nav.location(), {
      timeout: T.nav,
      message: 'the workbench should follow the regrouped release',
    })
    .toContain(`/metadata/${regrouped}`);
  const fresh = await app.api.get('/albums/{pid}', { path: { pid: regrouped } });
  expect(fresh.title).toBe(renamed);
});
