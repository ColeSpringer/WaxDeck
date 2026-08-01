import { test, expect, APIRequestContext, Page } from './fixtures';
import * as path from 'node:path';
import {
  ADMIN_PASS,
  ADMIN_USER,
  authed,
  clickThrough,
  ensureAdmin,
  typeInto,
  waitForLibrary,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The manual-upload journey: pick files in the web UI, group them as
// one album through the upload batch, watch the batch finalize into a
// single review entry, accept it, and find the titles in the library.
// The source files live in .run/upload-src - outside the scanned
// roots, so they only ever enter the library through this pipeline.


const uploadSrc = (name: string) =>
  path.join(__dirname, '..', '.run', 'upload-src', name);

async function loginAs(page: Page, username: string, password: string) {
  await page.goto('/');
  const user = page.getByRole('textbox', { name: 'Username' });
  await user.waitFor({ timeout: 30_000 });
  await typeInto(page, user, username);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), password);
  await page.getByRole('button', { name: 'Log in' }).click();
  // Settled on a destination every account has: this spec signs in as a
  // viewer with no upload rights too, and the curation group is hidden
  // from an account with nothing in it.
  await page
    .locator(sem(SemanticsIds.navDestination('settings')))
    .waitFor({ timeout: 30_000 });
}

type UploadRow = {
  id: string;
  fileName: string;
  state: string;
  batchId?: string;
  reviewEntryId?: string;
};

async function uploadRows(
  request: APIRequestContext,
  token: string,
): Promise<UploadRow[]> {
  const resp = await request.get('/api/v1/uploads?limit=100', authed(token));
  expect(resp.ok()).toBeTruthy();
  return ((await resp.json()).uploads ?? []) as UploadRow[];
}

test('two picked files group as one album and import through review', async ({
  page,
  request,
}) => {
  test.setTimeout(240_000);
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  await loginAs(page, ADMIN_USER, ADMIN_PASS);

  // Open the add sheet and choose the file upload.
  await clickThrough(
    page.locator(sem(SemanticsIds.addToLibrary)),
    page.locator(sem(SemanticsIds.addUploadFile)),
  );
  const chooser = page.waitForEvent('filechooser');
  await page.locator(sem(SemanticsIds.addUploadFile)).click({ force: true });
  await (await chooser).setFiles([
    uploadSrc('lantern-one.mp3'),
    uploadSrc('lantern-two.mp3'),
  ]);

  // Several files: the dialog asks the grouping; declare one album.
  await page.locator(sem(SemanticsIds.uploadGrouping)).waitFor({ timeout: 30_000 });
  await page.locator(sem(SemanticsIds.uploadGroupingOption('album'))).click({ force: true });
  await page.locator(sem(SemanticsIds.uploadMediaConfirm)).click({ force: true });

  // Both members stage under one batch and the finalize opens exactly
  // one review entry across them.
  let entryId = '';
  await expect(async () => {
    const rows = await uploadRows(request, token);
    const members = rows.filter(
      (r) =>
        (r.fileName === 'lantern-one.mp3' || r.fileName === 'lantern-two.mp3') &&
        r.batchId &&
        r.state === 'staged',
    );
    expect(members).toHaveLength(2);
    expect(members[0].batchId).toBe(members[1].batchId);
    expect(members[0].reviewEntryId, 'finalize linked the entry').toBeTruthy();
    expect(members[1].reviewEntryId).toBe(members[0].reviewEntryId);
    entryId = members[0].reviewEntryId!;
  }).toPass({ timeout: 60_000 });

  // The uploads screen shows the quota header and the batch group.
  await clickThrough(
    page.locator(sem(SemanticsIds.navGroup('curation'))),
    page.locator(sem(SemanticsIds.navDestination('uploads'))),
  );
  await clickThrough(
    page.locator(sem(SemanticsIds.navDestination('uploads'))),
    page.locator(sem(SemanticsIds.uploadQuota)),
  );

  // The entry settles (matching is off) and holds both tracks.
  await expect
    .poll(
      async () => {
        const resp = await request.get(
          `/api/v1/review/queue/${entryId}`,
          authed(token),
        );
        if (!resp.ok()) return 'missing';
        const entry = await resp.json();
        return entry.identifying ? 'identifying' : entry.status;
      },
      { timeout: 60_000, message: 'the album entry should settle to pending' },
    )
    .toBe('pending');
  const entry = await (
    await request.get(`/api/v1/review/queue/${entryId}`, authed(token))
  ).json();
  expect(entry.trackCount).toBe(2);

  // Accept as-is: the staged files enter the library.
  const decided = await request.post(
    `/api/v1/review/queue/${entryId}/decide`,
    { ...authed(token), data: { action: 'as-is' } },
  );
  expect(decided.ok()).toBeTruthy();

  const rescan = await request.post('/api/v1/library/rescan', authed(token));
  expect([202, 409]).toContain(rescan.status());
  await expect
    .poll(
      async () => {
        const resp = await request.get(
          '/api/v1/library/items?mediaType=music&limit=500',
          authed(token),
        );
        if (!resp.ok()) return [];
        const titles = ((await resp.json()).items ?? []).map(
          (i: { title: string }) => i.title,
        );
        return ['Paper Lanterns', 'River Static'].filter((t) =>
          titles.includes(t),
        );
      },
      { timeout: 60_000, message: 'the uploaded album should reach the library' },
    )
    .toEqual(['Paper Lanterns', 'River Static']);
});

test('a dropped file uploads through the drag-and-drop area', async ({
  page,
  request,
}) => {
  test.setTimeout(180_000);
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  // Solo sessions only: the parallel picker journey uploads the same
  // fixture as a batch member, which must not count here.
  const soloRows = async () =>
    (await uploadRows(request, token)).filter(
      (r) => r.fileName === 'lantern-two.mp3' && !r.batchId,
    );
  const before = (await soloRows()).length;

  await loginAs(page, ADMIN_USER, ADMIN_PASS);

  // A real file drag through CDP: the browser builds the drag store
  // from the host path, so the web plugin's entry traversal sees a
  // genuine file entry (a synthetic DataTransfer would hand it null).
  // Dispatched as a retried unit, like clickThrough: the canvas can
  // swallow a drop while the engine is mid-frame, and a missed drop
  // leaves no state behind, so dropping again is safe.
  const client = await page.context().newCDPSession(page);
  const size = page.viewportSize();
  expect(size).toBeTruthy();
  const x = size!.width / 2;
  const y = size!.height / 2;
  const data = {
    items: [],
    files: [uploadSrc('lantern-two.mp3')],
    dragOperationsMask: 1,
  };
  const dialog = page.locator(sem(SemanticsIds.uploadMediaConfirm));
  await expect(async () => {
    if (!(await dialog.isVisible())) {
      await client.send('Input.dispatchDragEvent', { type: 'dragEnter', x, y, data });
      await client.send('Input.dispatchDragEvent', { type: 'dragOver', x, y, data });
      await client.send('Input.dispatchDragEvent', { type: 'drop', x, y, data });
    }
    await dialog.waitFor({ timeout: 5_000 });
  }).toPass({ timeout: 60_000 });

  // One file: the dialog asks only the media type.
  await dialog.click({ force: true });

  // The solo session stages with its own review entry, no batch.
  await expect(async () => {
    const rows = await soloRows();
    expect(rows.length).toBe(before + 1);
    const fresh = rows[0];
    expect(fresh.state).toBe('staged');
    expect(fresh.reviewEntryId).toBeTruthy();
  }).toPass({ timeout: 60_000 });
});

test('accounts without upload rights see no upload affordances', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  // A plain account, no upload grant.
  const suffix = Date.now().toString(36);
  const created = await request.post('/api/v1/users', {
    ...authed(token),
    data: { username: `viewer-${suffix}`, password: 'viewer-pass-123' },
  });
  expect(created.status()).toBe(201);

  await loginAs(page, `viewer-${suffix}`, 'viewer-pass-123');

  // No add button, and no way into uploads: an account with nothing in
  // the curation group is not offered the group at all.
  await expect(page.locator(sem(SemanticsIds.addToLibrary))).toHaveCount(0);
  await expect(page.locator(sem(SemanticsIds.navGroup('curation')))).toHaveCount(0);
  await expect(page.locator(sem(SemanticsIds.navDestination('uploads')))).toHaveCount(0);
});
