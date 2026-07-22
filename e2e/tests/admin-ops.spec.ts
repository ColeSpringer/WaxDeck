import { test, expect, APIRequestContext } from '@playwright/test';
import {
  ADMIN_PASS,
  ADMIN_USER,
  authed,
  clickThrough,
  ensureAdmin,
  typeInto,
  waitForLibrary,
} from './helpers';

// The admin-and-ops surface, driven over the API against the live
// stack: the audit log answering "who deleted this playlist", the
// backup lifecycle through staged restore, signup requests and
// invites, the trash round trip, and read-only mode. The UI halves of
// these surfaces are covered by widget tests; these scenarios pin the
// contract a real deployment exercises.

async function firstItemPid(request: APIRequestContext, token: string): Promise<string> {
  const items = await request.get('/api/v1/library/items?limit=5', authed(token));
  expect(items.ok()).toBeTruthy();
  const body = await items.json();
  expect(body.items.length).toBeGreaterThan(0);
  return body.items[0].pid as string;
}

// The trash round trip briefly removes a file; picking the tail of a
// wide page keeps it away from the fixtures other parallel specs
// exercise by position or title.
async function lastItemPid(request: APIRequestContext, token: string): Promise<string> {
  const items = await request.get('/api/v1/library/items?limit=100&mediaType=music', authed(token));
  expect(items.ok()).toBeTruthy();
  const body = await items.json();
  expect(body.items.length).toBeGreaterThan(0);
  return body.items[body.items.length - 1].pid as string;
}

test('the audit log answers who deleted a playlist', async ({ request }) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const pid = await firstItemPid(request, token);

  const created = await request.post('/api/v1/playlists', {
    ...authed(token),
    data: { name: 'Doomed playlist', kind: 'static', itemPids: [pid] },
  });
  expect(created.ok()).toBeTruthy();
  const playlistPid = (await created.json()).pid as string;

  const del = await request.delete(`/api/v1/playlists/${playlistPid}`, authed(token));
  expect(del.status()).toBe(204);

  const audit = await request.get(
    '/api/v1/admin/audit?action=playlist.delete&limit=10',
    authed(token),
  );
  expect(audit.ok()).toBeTruthy();
  const events = (await audit.json()).events as Array<{
    action: string; actorName?: string; targetPid?: string; targetName?: string;
  }>;
  const hit = events.find((e) => e.targetPid === playlistPid);
  expect(hit, 'the deletion is on the record').toBeTruthy();
  expect(hit!.actorName).toBe('admin');
  expect(hit!.targetName).toBe('Doomed playlist');
});

test('a backup archive is written, downloadable, and stageable', async ({ request }) => {
  test.setTimeout(120_000);
  const token = await ensureAdmin(request);

  const started = await request.post('/api/v1/admin/backups', authed(token));
  // A concurrent run from a retry answers conflict; both converge on
  // polling the list for a finished archive.
  expect([202, 409]).toContain(started.status());

  let backup: { id: string; state: string; sizeBytes?: number } | undefined;
  await expect(async () => {
    const list = await request.get('/api/v1/admin/backups', authed(token));
    expect(list.ok()).toBeTruthy();
    const backups = (await list.json()).backups as Array<typeof backup & object>;
    backup = backups.find((b) => b!.state === 'done') as typeof backup;
    expect(backup, 'a finished backup appears').toBeTruthy();
  }).toPass({ timeout: 60_000 });

  expect(backup!.sizeBytes).toBeGreaterThan(0);
  const archive = await request.get(
    `/api/v1/admin/backups/${backup!.id}/archive`,
    authed(token),
  );
  expect(archive.ok()).toBeTruthy();
  expect(archive.headers()['content-type']).toContain('zip');
  expect((await archive.body()).length).toBe(backup!.sizeBytes);

  const staged = await request.post(
    `/api/v1/admin/backups/${backup!.id}/restore`,
    authed(token),
  );
  expect(staged.ok()).toBeTruthy();
  const plan = await staged.json();
  expect(plan.backupId).toBe(backup!.id);
  expect(plan.keyfilePresent).toBe(true);
  expect(plan.keyfileMatches).toBe(true);

  const read = await request.get('/api/v1/admin/backups/restore', authed(token));
  expect(read.ok()).toBeTruthy();

  // The staged backup refuses deletion; cancelling releases it.
  const refused = await request.delete(`/api/v1/admin/backups/${backup!.id}`, authed(token));
  expect(refused.status()).toBe(409);
  const cancel = await request.delete('/api/v1/admin/backups/restore', authed(token));
  expect(cancel.status()).toBe(204);
  const gone = await request.get('/api/v1/admin/backups/restore', authed(token));
  expect(gone.status()).toBe(404);
});

test('signup requests await approval and invites pre-approve', async ({ request }) => {
  const token = await ensureAdmin(request);
  const suffix = Date.now().toString(36);

  // Open signup off by default: the door answers forbidden.
  const closed = await request.post('/api/v1/auth/signup', {
    data: { username: `pending-${suffix}`, password: 'password123' },
  });
  expect(closed.status()).toBe(403);

  const settings = await request.get('/api/v1/admin/settings', authed(token));
  expect(settings.ok()).toBeTruthy();
  const current = await settings.json();
  const opened = await request.put('/api/v1/admin/settings', {
    ...authed(token),
    data: { ...current, signupEnabled: true },
  });
  expect(opened.ok()).toBeTruthy();

  // The login screen learns from the public bootstrap probe.
  const probe = await request.get('/api/v1/auth/bootstrap');
  expect((await probe.json()).signupEnabled).toBe(true);

  const signup = await request.post('/api/v1/auth/signup', {
    data: { username: `pending-${suffix}`, password: 'password123' },
  });
  expect(signup.status()).toBe(201);
  expect((await signup.json()).state).toBe('pending');

  // Pending accounts cannot log in.
  const refused = await request.post('/api/v1/auth/login', {
    data: { username: `pending-${suffix}`, password: 'password123' },
  });
  expect(refused.status()).toBe(401);

  const queue = await request.get('/api/v1/users/requests', authed(token));
  expect(queue.ok()).toBeTruthy();
  const pending = (await queue.json()).users.find(
    (u: { username: string }) => u.username === `pending-${suffix}`,
  );
  expect(pending).toBeTruthy();
  expect(pending.pending).toBe(true);

  const approved = await request.post(
    `/api/v1/users/requests/${pending.id}/approve`,
    { ...authed(token), data: { permissions: { download: true, delete: false, explicitContent: true, sharedOutputs: true, managePodcasts: true } } },
  );
  expect(approved.ok()).toBeTruthy();
  const login = await request.post('/api/v1/auth/login', {
    data: { username: `pending-${suffix}`, password: 'password123' },
  });
  expect(login.ok()).toBeTruthy();

  // Invites admit immediately, even with open signup back off.
  const closedAgain = await request.put('/api/v1/admin/settings', {
    ...authed(token),
    data: { ...current, signupEnabled: false },
  });
  expect(closedAgain.ok()).toBeTruthy();
  const invite = await request.post('/api/v1/invites', {
    ...authed(token),
    data: { note: 'e2e invite', maxUses: 1 },
  });
  expect(invite.status()).toBe(201);
  const inviteBody = await invite.json();
  expect(inviteBody.token).toBeTruthy();

  const invited = await request.post('/api/v1/auth/signup', {
    data: { username: `invited-${suffix}`, password: 'password123', inviteToken: inviteBody.token },
  });
  expect(invited.status()).toBe(201);
  expect((await invited.json()).state).toBe('active');
  const invitedLogin = await request.post('/api/v1/auth/login', {
    data: { username: `invited-${suffix}`, password: 'password123' },
  });
  expect(invitedLogin.ok()).toBeTruthy();

  // The list shows the spent invite without its token.
  const invites = await request.get('/api/v1/invites', authed(token));
  const listed = (await invites.json()).invites.find(
    (iv: { id: string }) => iv.id === inviteBody.id,
  );
  expect(listed.usedCount).toBe(1);
  expect(listed.token).toBeUndefined();
});

test('deleted items land in the trash and restore cleanly', async ({ request }) => {
  test.setTimeout(120_000);
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const pid = await lastItemPid(request, token);

  const plan = await request.post('/api/v1/library/items/delete', {
    ...authed(token),
    data: { pids: [pid], dryRun: true },
  });
  expect(plan.ok()).toBeTruthy();
  const planBody = await plan.json();
  expect(planBody.applied).toBe(false);
  expect(planBody.entries[0].files).toBeGreaterThan(0);

  const applied = await request.post('/api/v1/library/items/delete', {
    ...authed(token),
    data: { pids: [pid] },
  });
  expect(applied.ok()).toBeTruthy();
  expect((await applied.json()).applied).toBe(true);

  const trash = await request.get('/api/v1/admin/trash', authed(token));
  expect(trash.ok()).toBeTruthy();
  const entry = (await trash.json()).entries[0];
  expect(entry).toBeTruthy();

  const restore = await request.post(
    `/api/v1/admin/trash/${entry.id}/restore`,
    authed(token),
  );
  expect(restore.status()).toBe(204);

  // The restore re-scans the file back into the catalog.
  await expect(async () => {
    const item = await request.get(`/api/v1/items/${pid}`, authed(token));
    expect(item.ok()).toBeTruthy();
  }).toPass({ timeout: 60_000 });
});

test('read-only mode refuses uploads and releases', async ({ request }) => {
  const token = await ensureAdmin(request);
  const settings = await (await request.get('/api/v1/admin/settings', authed(token))).json();

  const on = await request.put('/api/v1/admin/settings', {
    ...authed(token),
    data: { ...settings, readOnly: true },
  });
  expect(on.ok()).toBeTruthy();
  try {
    const refused = await request.post('/api/v1/uploads', {
      ...authed(token),
      data: { fileName: 'nope.mp3', sizeBytes: 1024, mediaType: 'music' },
    });
    expect(refused.status()).toBe(409);
    expect((await refused.json()).code).toBe('read-only');
  } finally {
    const off = await request.put('/api/v1/admin/settings', {
      ...authed(token),
      data: { ...settings, readOnly: false },
    });
    expect(off.ok()).toBeTruthy();
  }
});

test('an exported archive imports back through the backups screen', async ({
  page,
  request,
}) => {
  test.setTimeout(180_000);
  const token = await ensureAdmin(request);

  // A genuine archive to round-trip: create (or reuse) one and
  // download its bytes — the import endpoint validates real WaxDeck
  // backups, so a synthetic zip would be refused.
  const started = await request.post('/api/v1/admin/backups', authed(token));
  expect([202, 409]).toContain(started.status());
  let archiveId = '';
  await expect(async () => {
    const list = await request.get('/api/v1/admin/backups', authed(token));
    expect(list.ok()).toBeTruthy();
    const done = ((await list.json()).backups as Array<{ id: string; state: string }>).find(
      (b) => b.state === 'done',
    );
    expect(done, 'a finished backup appears').toBeTruthy();
    archiveId = done!.id;
  }).toPass({ timeout: 60_000 });
  const archive = await request.get(
    `/api/v1/admin/backups/${archiveId}/archive`,
    authed(token),
  );
  expect(archive.ok()).toBeTruthy();
  const fs = await import('node:fs/promises');
  const os = await import('node:os');
  const pathMod = await import('node:path');
  const zipPath = pathMod.join(
    await fs.mkdtemp(pathMod.join(os.tmpdir(), 'waxdeck-e2e-')),
    'roundtrip.zip',
  );
  await fs.writeFile(zipPath, await archive.body());

  // Import it back through the backups screen.
  const sem = (id: string) => `[flt-semantics-identifier="${id}"]`;
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();
  await clickThrough(page.locator(sem('curation-menu')), page.locator(sem('curation-backups')));
  await clickThrough(page.locator(sem('curation-backups')), page.locator(sem('backup-import')));

  const chooser = page.waitForEvent('filechooser');
  await page.locator(sem('backup-import')).click({ force: true });
  await (await chooser).setFiles(zipPath);

  // The imported archive joins the listing with its own trigger.
  await expect(async () => {
    const list = await request.get('/api/v1/admin/backups', authed(token));
    expect(list.ok()).toBeTruthy();
    const backups = (await list.json()).backups as Array<{
      trigger: string;
      state: string;
    }>;
    expect(
      backups.some((b) => b.trigger === 'imported' && b.state === 'done'),
      'the imported archive appears in the list',
    ).toBeTruthy();
  }).toPass({ timeout: 60_000 });
});
