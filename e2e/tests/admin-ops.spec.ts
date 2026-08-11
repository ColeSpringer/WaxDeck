import { test, expect } from './fixtures';
import { J, T } from './driver';

// The admin-and-ops surface, driven over the API against the live
// stack: the audit log answering "who deleted this playlist", the
// backup lifecycle through staged restore, signup requests and
// invites, the trash round trip, and read-only mode. The UI halves of
// these surfaces are covered by widget tests; these scenarios pin the
// contract a real deployment exercises.
//
// Everything here is server-global - the settings row, the backup set,
// the trash, the library table - so this file is its own project, in
// the chain rather than beside it. It is no longer one worker in order,
// though: what forced that was server-wide read-only, which refuses
// every write on the stack while it is on, and that test now has a
// project of its own after this one (admin-readonly.spec.ts). What is
// left needs serializing only where two tests share one surface, which
// is the backup set and nothing else - hence one `describe.serial` and
// four tests that run beside each other.

test('the audit log answers who deleted a playlist', async ({ app }) => {
  const items = await app.api.get('/library/items', { query: { limit: 5 } });
  const pid = (items.items ?? [])[0]?.pid;
  expect(pid, 'the fixture library should hold an item').toBeTruthy();

  const playlistPid = await app.seed.createPlaylist('Doomed playlist', [pid!]);
  const del = await app.api.raw.delete('/playlists/{pid}', { path: { pid: playlistPid } });
  expect(del.status()).toBe(204);

  const audit = await app.api.get('/admin/audit', {
    query: { action: 'playlist.delete', limit: 10 },
  });
  const hit = (audit.events ?? []).find((e) => e.targetPid === playlistPid);
  expect(hit, 'the deletion is on the record').toBeTruthy();
  expect(hit!.actorName).toBe(app.account.username);
  expect(hit!.targetName).toBe('Doomed playlist');
});

// Both of these read the backup set - one creates an archive and
// stages it, the other exports and imports one back - and there is
// one backup set on the server. Serial against each other, and only
// against each other: the rest of this file owns different global
// surfaces and runs beside them.
test.describe.serial('backup lifecycle', () => {
  test('a backup archive is written, downloadable, and stageable', async ({ app }) => {
    const started = await app.api.raw.post('/admin/backups');
    // A concurrent run from a retry answers conflict; both converge on
    // polling the list for a finished archive.
    expect([202, 409]).toContain(started.status());

    let backup: { id: string; state: string; sizeBytes?: number } | undefined;
    await expect(async () => {
      const list = await app.api.get('/admin/backups');
      backup = (list.backups ?? []).find((b) => b.state === 'done');
      expect(backup, 'a finished backup appears').toBeTruthy();
    }).toPass({ timeout: T.fetch });

    expect(backup!.sizeBytes).toBeGreaterThan(0);
    const archive = await app.api.raw.get('/admin/backups/{backupId}/archive', {
      path: { backupId: backup!.id },
    });
    expect(archive.ok()).toBeTruthy();
    expect(archive.headers()['content-type']).toContain('zip');
    expect((await archive.body()).length).toBe(backup!.sizeBytes);

    // The archive serves ranges, so an interrupted download of a
    // multi-gigabyte one resumes rather than starting over.
    const partial = await app.api.raw.get('/admin/backups/{backupId}/archive', {
      path: { backupId: backup!.id },
      headers: { Range: 'bytes=8-23' },
    });
    expect(partial.status()).toBe(206);
    expect(partial.headers()['content-range']).toBe(`bytes 8-23/${backup!.sizeBytes}`);
    expect((await partial.body()).length).toBe(16);

    const plan = await app.api.post('/admin/backups/{backupId}/restore', {
      path: { backupId: backup!.id },
    });
    expect(plan.backupId).toBe(backup!.id);
    expect(plan.keyfilePresent).toBe(true);
    expect(plan.keyfileMatches).toBe(true);

    expect((await app.api.raw.get('/admin/backups/restore')).ok()).toBeTruthy();

    // The staged backup refuses deletion; cancelling releases it.
    const refused = await app.api.raw.delete('/admin/backups/{backupId}', {
      path: { backupId: backup!.id },
    });
    expect(refused.status()).toBe(409);
    const cancel = await app.api.raw.delete('/admin/backups/restore');
    expect(cancel.status()).toBe(204);
    expect((await app.api.raw.get('/admin/backups/restore')).status()).toBe(404);
  });

  test('an exported archive imports back through the backups screen', async ({ app }) => {
    test.setTimeout(J.long);

    // A genuine archive to round-trip: create (or reuse) one and download
    // its bytes - the import endpoint validates real WaxDeck backups, so a
    // synthetic zip would be refused.
    const started = await app.api.raw.post('/admin/backups');
    expect([202, 409]).toContain(started.status());
    let archiveId = '';
    await expect(async () => {
      const list = await app.api.get('/admin/backups');
      const done = (list.backups ?? []).find((b) => b.state === 'done');
      expect(done, 'a finished backup appears').toBeTruthy();
      archiveId = done!.id;
    }).toPass({ timeout: T.fetch });
    const archive = await app.api.raw.get('/admin/backups/{backupId}/archive', {
      path: { backupId: archiveId },
    });
    expect(archive.ok()).toBeTruthy();
    const fs = await import('node:fs/promises');
    const os = await import('node:os');
    const pathMod = await import('node:path');
    const zipPath = pathMod.join(
      await fs.mkdtemp(pathMod.join(os.tmpdir(), 'waxdeck-e2e-')),
      'roundtrip.zip',
    );
    await fs.writeFile(zipPath, await archive.body());

    // Import it back through the backups screen, reached the way an
    // administrator reaches it: the console, then its own section list.
    await app.nav.to('adminBackups');
    await app.admin.importBackup(zipPath);

    // The imported archive joins the listing with its own trigger.
    await expect(async () => {
      const list = await app.api.get('/admin/backups');
      expect(
        (list.backups ?? []).some((b) => b.trigger === 'imported' && b.state === 'done'),
        'the imported archive appears in the list',
      ).toBeTruthy();
    }).toPass({ timeout: T.fetch });
  });
});

test('signup requests await approval and invites pre-approve', async ({ app }) => {
  const anon = app.api.as('');
  const suffix = Date.now().toString(36);
  const pendingName = `pending-${suffix}`;
  const invitedName = `invited-${suffix}`;
  const password = 'password123';

  // Open signup off by default: the door answers forbidden.
  //
  // The signup limiter is a per-source-IP budget of five attempts in
  // fifteen minutes - every outcome burns it, successes included - and
  // every test on the stack shares one address. The suite spends four of
  // those five per run: this refusal, the pending signup and the invited
  // one below, and signup-ui's walk-up. So roughly ONE full run fits in a
  // quarter of an hour before the next signup is refused 429, and the
  // spec that meets it is signup-ui, which fails looking like a broken
  // form rather than like a limiter.
  //
  // Under the soak that is survivable: the lockout starts at thirty
  // seconds and the attempts are spread across a pass. Iterating locally
  // it is not, and the answer is to restart the stack - the limiter is
  // in memory. What it is NOT is a reason to stop asserting this: a
  // closed door answering forbidden is the whole point of the switch.
  const closed = await anon.raw.post('/auth/signup', {
    data: { username: pendingName, password },
  });
  expect(closed.status()).toBe(403);

  // Opened here and closed in the `finally`, like the read-only switch
  // in admin-readonly.spec.ts. It is server-global: a run that dies between the two writes
  // leaves open signup on for every later run on this stack, and
  // signup-ui - whose whole subject is the invite path an account meets
  // when open signup is OFF - then fails somewhere else entirely.
  const current = await app.api.get('/admin/settings');
  await app.api.put('/admin/settings', { data: { ...current, signupEnabled: true } });
  try {
    // The login screen learns from the public bootstrap probe.
    expect((await anon.get('/auth/bootstrap')).signupEnabled).toBe(true);

    const signup = await anon.post('/auth/signup', {
      data: { username: pendingName, password },
    });
    expect(signup.state).toBe('pending');

    // Pending accounts cannot log in.
    const refused = await anon.raw.post('/auth/login', {
      data: { username: pendingName, password },
    });
    expect(refused.status()).toBe(401);

    const queue = await app.api.get('/users/requests');
    const pending = (queue.users ?? []).find((u) => u.username === pendingName);
    expect(pending, 'the request is queued').toBeTruthy();
    expect(pending!.pending).toBe(true);

    await app.api.post('/users/requests/{userId}/approve', {
      path: { userId: pending!.id },
      data: {
        permissions: {
          download: true,
          delete: false,
          explicitContent: true,
          sharedOutputs: true,
          managePodcasts: true,
        },
      },
    });
    expect(
      (await anon.raw.post('/auth/login', { data: { username: pendingName, password } })).ok(),
    ).toBeTruthy();

    // Invites admit immediately, even with open signup back off.
    await app.api.put('/admin/settings', { data: { ...current, signupEnabled: false } });
    const invite = await app.api.post('/invites', {
      data: { note: 'e2e invite', maxUses: 1 },
    });
    expect(invite.token).toBeTruthy();

    const invited = await anon.post('/auth/signup', {
      data: { username: invitedName, password, inviteToken: invite.token },
    });
    expect(invited.state).toBe('active');
    expect(
      (await anon.raw.post('/auth/login', { data: { username: invitedName, password } })).ok(),
    ).toBeTruthy();

    // The list shows the spent invite without its token.
    const listed = ((await app.api.get('/invites')).invites ?? []).find(
      (iv) => iv.id === invite.id,
    );
    expect(listed!.usedCount).toBe(1);
    // The contract does not give a listed invite a token at all, so this
    // is belt to the compiler's braces: what a spent invite must never do
    // is hand its secret back to a listing.
    expect(Object.keys(listed!), 'a listed invite carries no token').not.toContain('token');
  } finally {
    await app.api.put('/admin/settings', { data: { ...current, signupEnabled: false } });
  }
});

test('deleted items land in the trash and restore cleanly', async ({ app }) => {
  // The tail of a wide page: the round trip briefly removes a file, and
  // a reused stack carries earlier runs' uploads, so this keeps clear of
  // the fixtures other specs name by title.
  const items = await app.api.get('/library/items', {
    query: { limit: 100, mediaType: 'music' },
  });
  const rows = items.items ?? [];
  expect(rows.length).toBeGreaterThan(0);
  const pid = rows[rows.length - 1].pid;

  const plan = await app.api.post('/library/items/delete', {
    // `mode` and `dryRun` spelled out because the contract marks them
    // required: the hand-typed body this replaced left both off and the
    // server defaulted them, so the suite was asking for a delete the
    // app itself would not ask for.
    data: { pids: [pid], mode: 'trash' as const, dryRun: true },
  });
  expect(plan.applied).toBe(false);
  expect(plan.entries[0].files).toBeGreaterThan(0);

  const applied = await app.api.post('/library/items/delete', {
    data: { pids: [pid], mode: 'trash' as const, dryRun: false },
  });
  expect(applied.applied).toBe(true);

  const trash = await app.api.get('/admin/trash');
  const entry = (trash.entries ?? [])[0];
  expect(entry, 'the delete left a trash entry').toBeTruthy();

  const restore = await app.api.raw.post('/admin/trash/{trashId}/restore', {
    path: { trashId: entry!.id },
  });
  expect(restore.status()).toBe(204);

  // The restore re-scans the file back into the catalog.
  await expect(async () => {
    expect((await app.api.raw.get('/items/{pid}', { path: { pid } })).ok()).toBeTruthy();
  }).toPass({ timeout: T.fetch });
});

// Creating a library at runtime has to reach the streaming sidecar, or
// the root browses and downloads while streaming waits for a restart.
// The stack runs a file-configured sidecar, so this drives the real
// loop: WaxDeck rewrites the roots array, posts /roots/reload, and the
// sidecar opens the new root with os.Root while reconciling. A path it
// cannot see fails there, and the reason lands on the audit entry.
//
// The new root is deliberately empty. The reload is what is under test,
// and adding media here would shift the fixture listings the specs
// running beside this one page through.
test('a library created at runtime reaches the streaming sidecar', async ({ app }) => {
  const fs = await import('node:fs/promises');
  const pathMod = await import('node:path');

  // run-stack.sh builds the stack under e2e/.run, and playwright runs
  // from e2e/ (the config's directory), so the sidecar and this test
  // name the same absolute paths.
  const runDir = pathMod.resolve(process.cwd(), '.run');
  const extra = pathMod.join(runDir, 'runtime-root');
  await fs.mkdir(extra, { recursive: true });

  const created = await app.api.post('/libraries', {
    data: { name: 'runtime', path: extra, media: 'music' as const, managed: false },
  });
  const libraryPid = created.pid;

  // The 201 says so as well as the audit entry: the administrator who
  // made the change is looking at the response, and reporting a plain
  // success while streaming is broken is a silent partial failure.
  expect(created.streamingWarning, 'the create reports streaming as working').toBeUndefined();
  expect(created.path, 'the create names the root it registered').toBe(extra);

  // The sidecar's own reconcile is the verification: a refusal (a path
  // it cannot open, a reload it does not serve) is recorded here.
  const audit = await app.api.get('/admin/audit', {
    query: { action: 'library.create', limit: 10 },
  });
  const hit = (audit.events ?? []).find((e) => e.targetPid === libraryPid);
  expect(hit, 'the create is on the record').toBeTruthy();
  expect(
    hit!.detail?.streamingWarning,
    'the sidecar reconciled the new root without a restart',
  ).toBeUndefined();

  // The name is the sidecar's addressing key, so one already mapped
  // there is refused even though it is not in the library table: the
  // podcast download root is exactly that case.
  const clash = await app.api.raw.post('/libraries', {
    data: {
      name: 'podcasts',
      path: pathMod.join(runDir, 'runtime-clash'),
      media: 'music' as const,
      managed: false,
    },
  });
  expect(clash.status()).toBe(409);
});
