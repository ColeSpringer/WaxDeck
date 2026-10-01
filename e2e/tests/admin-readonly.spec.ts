import { test, expect } from './fixtures';
import { T } from './driver';
import { clickUntilRequested } from './driver/gestures';
import { SemanticsIds } from './semantics-ids';

// The read-only switches, server-wide and per library: each refuses writes
// the rest of the stack makes, so they run in a project of their own, and
// one at a time.
test.describe.configure({ mode: 'serial' });

test('read-only mode refuses uploads and releases', async ({ app }) => {
  const settings = await app.api.get('/admin/settings');

  await app.api.put('/admin/settings', { data: { ...settings, readOnly: true } });
  try {
    const refused = await app.api.raw.post('/uploads', {
      data: { fileName: 'nope.mp3', sizeBytes: 1024, mediaType: 'music' },
    });
    expect(refused.status()).toBe(409);
    expect((await refused.json()).code).toBe('read-only');
  } finally {
    await app.api.put('/admin/settings', { data: { ...settings, readOnly: false } });
  }
});

// A library's flag lives in the catalog: the switch sets it, the listing
// reports it, a delete under it is refused, and the trash names each
// entry's library.
test('a read-only library keeps its files and the trash names it', async ({ app }) => {
  const { libraries } = await app.api.get('/libraries');
  const lib = libraries.find((l) => l.name === 'lib');
  expect(lib, 'the configured library').toBeTruthy();
  const pid = lib!.pid;

  const track = await app.seed.disposableTrack();
  await app.api.post('/library/items/delete', { data: { pids: [track], mode: 'trash' as const, dryRun: false } });
  const entry = ((await app.api.get('/admin/trash')).entries ?? [])[0];
  try {
    expect(entry?.libraryPid, 'the trash names the library').toBe(pid);
  } finally {
    // Back whatever the check said, or a retry finds the track gone.
    if (entry) {
      const restore = await app.api.raw.post('/admin/trash/{trashId}/restore', { path: { trashId: entry.id } });
      expect(restore.status()).toBe(204);
    }
  }
  await expect(async () => {
    expect((await app.api.raw.get('/items/{pid}', { path: { pid: track } })).ok()).toBeTruthy();
  }).toPass({ timeout: T.fetch });

  await app.nav.enter('adminLibraries');
  try {
    await clickUntilRequested(app.page, app.admin.control(SemanticsIds.libraryReadOnly(pid)), (r) =>
      r.url().includes('/read-only'),
    );
    await expect(async () => {
      const listed = (await app.api.get('/libraries')).libraries.find((l) => l.pid === pid);
      expect(listed?.readOnly, 'the listing carries the flag').toBe(true);
    }).toPass({ timeout: T.fetch });

    const refused = await app.api.raw.post('/library/items/delete', {
      data: { pids: [track], mode: 'trash' as const, dryRun: false },
    });
    expect(refused.status()).toBe(409);
    expect((await refused.json()).code).toBe('read-only');
  } finally {
    await app.api.put('/libraries/{pid}/read-only', { path: { pid }, data: { readOnly: false } });
  }
});
