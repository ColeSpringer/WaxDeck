import * as fs from 'node:fs';
import * as path from 'node:path';
import type { Request } from '@playwright/test';
import { test, expect } from './fixtures';
import { J, T, chooseFromMenu, clickThrough, clickUntilRequested, retryCatalogBusy } from './driver';
import { removeLibrariesNamed, removeLibraryIfThere } from './driver/libraries';
import { SemanticsIds } from './semantics-ids';

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

// An edit is recorded with what it changed, field by field and from and to,
// so "who gave this account that name" has an answer that is not a guess;
// saving what the account already holds is not an event.
test('the audit log says what an account edit changed', async ({ app, otherAccount }) => {
  const member = await otherAccount('renamed');
  const { user } = await app.api.as(member.token).get('/auth/session');
  const userId = user!.id;
  const label = `Renamed ${Date.now().toString(36)}`;
  const edits = async () =>
    (await app.api.get('/admin/audit', { query: { action: 'user.update', targetPid: userId } }))
      .events ?? [];
  const before = (await edits()).length;

  await app.api.patch('/users/{userId}', { path: { userId }, data: { displayName: label } });
  const recorded = await edits();
  expect(recorded.length, 'the edit is on the record').toBe(before + 1);
  expect(recorded[0].actorName).toBe(app.account.username);
  const changes = (recorded[0].detail?.changes ?? {}) as Record<string, { from: unknown; to: unknown }>;
  expect(Object.keys(changes), 'only what the edit changed').toEqual(['displayName']);
  expect(changes.displayName.to).toBe(label);

  await app.api.patch('/users/{userId}', { path: { userId }, data: { displayName: label } });
  expect((await edits()).length, 'a save that changes nothing records nothing').toBe(before + 1);
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

// A store-only zip, built here because the suite carries no archive
// library and an account data export is the one upload with no server
// endpoint that produces one.
function storeZip(entries: { name: string; body: string }[]): Buffer {
  const crcTable = Array.from({ length: 256 }, (_, n) => {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    return c >>> 0;
  });
  const crc32 = (buf: Buffer) => {
    let c = 0xffffffff;
    for (const byte of buf) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const locals: Buffer[] = [];
  const central: Buffer[] = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    const data = Buffer.from(entry.body, 'utf8');
    const sum = crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4); // version needed
    local.writeUInt16LE(0, 6); // flags
    local.writeUInt16LE(0, 8); // stored
    local.writeUInt32LE(sum, 14);
    local.writeUInt32LE(data.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    locals.push(local, name, data);

    const dir = Buffer.alloc(46);
    dir.writeUInt32LE(0x02014b50, 0);
    dir.writeUInt16LE(20, 4);
    dir.writeUInt16LE(20, 6);
    dir.writeUInt16LE(0, 8);
    dir.writeUInt16LE(0, 10);
    dir.writeUInt32LE(sum, 16);
    dir.writeUInt32LE(data.length, 20);
    dir.writeUInt32LE(data.length, 24);
    dir.writeUInt16LE(name.length, 28);
    dir.writeUInt32LE(offset, 42);
    central.push(dir, name);
    offset += local.length + name.length + data.length;
  }
  const body = Buffer.concat(locals);
  const directory = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12);
  end.writeUInt32LE(body.length, 16);
  return Buffer.concat([body, directory, end]);
}

// The whole staged-export path over the real stack: an account data
// export is uploaded, recognised, and read by an import that lands on
// somebody else's account. A dry run, because what is under test is
// the matching and the plumbing rather than a write nothing here can
// undo on a shared server.
test('a data export imports onto another account', async ({ app, otherAccount }) => {
  // Named tracks, because the export carries no identifiers: what the
  // import has to match on is the artist and the title, so a fixture
  // that carries neither would prove nothing about the matching.
  const items = await app.api.get('/library/items', {
    query: { mediaType: 'music', limit: 50 },
  });
  const tracks = (items.items ?? []).filter((i) => i.artist && i.title).slice(0, 2);
  expect(tracks.length, 'the fixture library should hold named music').toBeGreaterThan(0);

  const plays = tracks.map((t) => ({
    ts: '2026-02-01T10:00:00Z',
    ms_played: 120000,
    master_metadata_track_name: t.title,
    master_metadata_album_artist_name: t.artist ?? '',
    master_metadata_album_album_name: t.album ?? '',
  }));
  const archive = storeZip([
    {
      name: 'Spotify Account Data/Streaming_History_Audio_2026_1.json',
      body: JSON.stringify(plays),
    },
  ]);

  const staged = await app.api.raw.upload('/admin/migrations/exports', archive);
  expect(staged.status(), await staged.text()).toBe(201);
  const exportRow = await staged.json();
  expect(exportRow.source).toBe('spotify');
  expect(exportRow.files).toHaveLength(1);

  const target = await otherAccount('import-target');
  const session = await app.api.as(target.token).get('/auth/session');
  const started = await app.api.post('/admin/migrations', {
    data: {
      source: 'spotify',
      exportId: exportRow.pid,
      accountId: session.user!.id,
      dryRun: true,
    },
  });
  expect(started.id, 'the import answers a task to follow').toBeTruthy();
  expect(started.type).toBe('import-spotify');

  try {
    await expect(async () => {
      const task = await app.api.get('/tools/tasks/{taskId}', {
        path: { taskId: started.id },
      });
      expect(task.state, `the import should finish: ${JSON.stringify(task.summary)}`).toBe('done');
      const summary = (task.summary ?? {}) as Record<string, unknown>;
      expect(
        Number(summary.matched ?? 0),
        `the export's plays should match the library they were named from: ${JSON.stringify(task)}`,
      ).toBeGreaterThan(0);
    }).toPass({ timeout: T.fetch });
  } finally {
    // A dry run deliberately keeps the archive, so this one hands it
    // back rather than leaving a household's listening history on the
    // shared stack until the expiry sweep reaches it a day later. In a
    // finally, because a run that failed above is exactly the one that
    // would otherwise leave it there.
    const discarded = await app.api.raw.delete('/admin/migrations/exports/{exportId}', {
      path: { exportId: exportRow.pid },
    });
    expect(discarded.status()).toBe(204);
  }
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
  const pid = await app.seed.disposableTrack();

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

// A delete the filesystem will not take is refused in words and moves
// nothing: the file stays, and the audit records the refusal rather than
// a delete. The Locked Book sits alone in its folder, so locking the
// folder reaches no other test's files.
test('a delete the filesystem refuses is said and audited as refused', async ({ app }) => {
  test.skip(
    process.platform === 'win32' || process.getuid?.() === 0,
    'a folder cannot be made unwritable to this process here',
  );
  const book = await app.seed.book('The Locked Book');
  const [file] = (await app.api.get('/items/{pid}/files', { path: { pid: book.pid } })).files;
  expect(file?.path, 'an administrator reads where the file is').toBeTruthy();
  const folder = path.dirname(file.path!);
  const mode = fs.statSync(folder).mode & 0o7777;
  await app.nav.open(`/books/${book.pid}`, app.books.resume());

  // The delete itself, not the dialog's preview of it.
  const isDelete = (r: Request) =>
    r.method() === 'POST' && r.url().endsWith('/library/items/delete') && r.postDataJSON()?.dryRun === false;
  fs.chmodSync(folder, 0o555);
  try {
    // A sibling's scan or removal can hold the file-mutation scope as the
    // confirm lands, which refuses it as catalog-busy with the dialog
    // already gone: the delete is asked for again once the scope is free.
    for (let attempt = 1; ; attempt++) {
      await chooseFromMenu(
        app.books.control(SemanticsIds.bookOverflow),
        app.books.control(SemanticsIds.itemMenuDelete),
        { settled: app.books.control(SemanticsIds.itemDeleteConfirm) },
      );
      const answered = app.page.waitForResponse((r) => isDelete(r.request()), { timeout: T.fetch });
      await clickUntilRequested(app.page, app.books.control(SemanticsIds.itemDeleteConfirm), isDelete);
      const response = await answered;
      if (response.status() === 409 && (await response.json()).code === 'catalog-busy' && attempt < 5) {
        await expect
          .poll(
            async () => {
              const list = await app.api.get('/jobs', { query: { limit: 50 } });
              return (list.jobs ?? []).filter((j) => j.state === 'running').length;
            },
            { timeout: T.fetch, message: 'the catalog job holding the scope should end' },
          )
          .toBe(0);
        continue;
      }
      await expect(app.books.text("The server cannot write to that library's folder")).toBeVisible({
        timeout: T.nav,
      });
      break;
    }
  } finally {
    fs.chmodSync(folder, mode);
  }

  expect(fs.existsSync(file.path!), 'the refused file stays where it was').toBeTruthy();
  const audit = await app.api.get('/admin/audit', {
    query: { action: 'items.delete.refused', limit: 20 },
  });
  const refused = (audit.events ?? []).find((e) =>
    ((e.detail?.pids as string[] | undefined) ?? []).includes(book.pid),
  );
  expect(refused, 'the refusal is on the record').toBeTruthy();
});

// The delete dialog names what goes by its place in the library before
// anything moves. Long Division is alone on its album, so the album's
// first row is the track, and a preview deletes nothing.
test('deleting a track from its row menu previews the file', async ({ app }) => {
  const track = await app.seed.item('Long Division');
  const [file] = (await app.api.get('/items/{pid}/files', { path: { pid: track.pid } })).files;
  await app.music.openAlbumOf(track.pid);
  const paths = app.music.control(SemanticsIds.itemDeletePaths);
  await chooseFromMenu(
    app.music.control(SemanticsIds.albumTrackMore(0)),
    app.music.control(SemanticsIds.itemMenuDelete),
    { settled: paths },
  );
  await expect
    .poll(async () => (await paths.getAttribute('aria-label')) ?? (await paths.textContent()) ?? '', {
      timeout: T.fetch,
      message: 'the preview should name the file',
    })
    .toContain(file.name);

  await app.page.keyboard.press('Escape');
  await expect(paths).toBeHidden();
  expect((await app.api.raw.get('/items/{pid}', { path: { pid: track.pid } })).ok()).toBeTruthy();
});

// A merge writes its file beside the book in the book's own library. Kept
// originals stay whole and the merged copy gets a folder of its own;
// deleting the copy for good afterwards leaves a kept stack the same two
// parts to merge next run.
test('an admin merges a book from its page and it stays in its library', async ({ app }) => {
  test.setTimeout(J.long);
  const book = await app.seed.book('The Merge Book');
  const before = await app.api.get('/books/{pid}', { path: { pid: book.pid } });
  expect(before.parts.length, 'the merge fixture is two files').toBe(2);
  const [part] = (await app.api.get('/items/{pid}/files', { path: { pid: book.pid } })).files;
  // A merged copy an earlier run left on a reused stack holds the name
  // this merge gives, which the server refuses to take from it. It goes
  // first; its title is not the original's.
  const listed = await app.api.tryGet('/library/items', { query: { mediaType: 'audiobook' } });
  const stale = (listed?.items ?? [])
    .filter((it) => it.title === 'The Merge Book (Merged)' && it.pid !== book.pid)
    .map((it) => it.pid);
  if (stale.length > 0) {
    await app.api.raw.post('/library/items/delete', {
      data: { pids: stale, mode: 'permanent' as const, dryRun: false },
    });
  }
  await app.nav.open(`/books/${book.pid}`, app.books.resume());

  await chooseFromMenu(
    app.books.control(SemanticsIds.bookOverflow),
    app.books.control(SemanticsIds.bookMerge),
    { settled: app.books.control(SemanticsIds.bookMergeConfirm) },
  );
  const keep = app.books.control(SemanticsIds.bookMergeKeep);
  // Toggled and read back rather than fired blind: a tap can land while
  // the dialog settles and be lost, and a merge that ran without keeping
  // the originals would trash the fixture's parts. The click fires only
  // on a read that found the switch off; a read of nothing (the node
  // re-creating) polls again.
  await expect
    .poll(
      async () => {
        const on = await keep.getAttribute('aria-checked');
        if (on === 'false') {
          await keep.click();
          // The node redraws a frame after the tap, later on a loaded
          // run: wait for the change before reading again, so a stale
          // read cannot click the switch back off.
          await expect(keep)
            .toHaveAttribute('aria-checked', 'true', { timeout: T.step })
            .catch(() => {});
        }
        return on;
      },
      { timeout: T.nav, message: 'the keep-originals switch should read on' },
    )
    .toBe('true');
  await expect(keep, 'the switch still reads on as the merge is confirmed').toHaveAttribute('aria-checked', 'true');
  const queued = app.page.waitForResponse(
    (r) => r.url().includes(`/books/${book.pid}/merge`) && r.request().method() === 'POST',
  );
  await clickThrough(
    app.books.control(SemanticsIds.bookMergeConfirm),
    app.books.text('Queued. Follow it in Tasks.'),
  );
  const taskId = ((await (await queued).json()) as { id: string }).id;

  let done = await app.api.get('/tools/tasks/{taskId}', { path: { taskId } });
  await expect
    .poll(
      async () => {
        done = await app.api.get('/tools/tasks/{taskId}', { path: { taskId } });
        return done.state;
      },
      { timeout: J.long, message: 'the merge should finish' },
    )
    .toBe('done');
  const merged = done.resultPids?.[0];
  expect(merged, 'the task names the merged book').toBeTruthy();
  expect(merged, 'the merged copy is a book of its own').not.toBe(book.pid);
  const mergedDir = path.join(path.dirname(path.dirname(part.path!)), 'The Merge Book (Merged)');
  const [out] = (await app.api.get('/items/{pid}/files', { path: { pid: merged! } })).files;
  // What the cleanup may delete: the merged copy, known by its folder,
  // and never the original, which a reused stack could not get back.
  const isCopy = merged !== book.pid && out !== undefined && path.dirname(out.path!) === mergedDir;
  try {
    expect(path.dirname(out.path!)).toBe(mergedDir);
    expect(out.libraryPid, 'the merged book stays in its library').toBe(part.libraryPid);
    const original = await app.api.get('/books/{pid}', { path: { pid: book.pid } });
    expect(original.parts.length, 'the kept original stays whole').toBe(2);
    const audit = await app.api.get('/admin/audit', { query: { action: 'book.merge', limit: 20 } });
    expect(
      (audit.events ?? []).find((e) => e.detail?.result === merged),
      'the merge is on the record',
    ).toBeTruthy();
  } finally {
    // Waited out past a sibling's scan, and swallowed otherwise, so a
    // refused cleanup cannot hide the assertion that failed.
    if (isCopy) {
      await retryCatalogBusy(() =>
        app.api.post('/library/items/delete', {
          data: { pids: [merged!], mode: 'permanent' as const, dryRun: false },
        }),
      ).catch(() => {});
    }
  }
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
test('a library created at runtime reaches the streaming sidecar and leaves it on removal', async ({
  app,
}) => {
  // Long: the create rescans every root, and the removal waits out that
  // scan's hold on the catalog.
  test.setTimeout(J.long);
  const fs = await import('node:fs/promises');
  const pathMod = await import('node:path');

  // run-stack.sh builds the stack under e2e/.run, and playwright runs
  // from e2e/ (the config's directory), so the sidecar and this test
  // name the same absolute paths.
  const runDir = pathMod.resolve(process.cwd(), '.run');
  const extra = pathMod.join(runDir, 'runtime-root');
  await fs.mkdir(extra, { recursive: true });
  const sidecarNames = async () =>
    (
      JSON.parse(await fs.readFile(pathMod.join(runDir, 'waxflow.json'), 'utf8')) as {
        roots: { name: string }[];
      }
    ).roots.map((r) => r.name);

  // An earlier attempt that failed may have left its library, whose name
  // and folder this one needs.
  await removeLibrariesNamed(app.api, 'runtime');
  const created = await app.api.post('/libraries', {
    data: { name: 'runtime', path: extra, media: 'music' as const, managed: false },
  });
  const libraryPid = created.pid;
  try {
    // The 201 says so as well as the audit entry: the administrator who
    // made the change is looking at the response, and reporting a plain
    // success while streaming is broken is a silent partial failure.
    expect(created.streamingWarning, 'the create reports streaming as working').toBeUndefined();
    expect(created.path, 'the create names the root it registered').toBe(extra);
    expect(await sidecarNames(), 'the sidecar file names the new root').toContain('runtime');

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

    // Removing it takes it back out the same way: the catalog lets go of
    // the folder, whose files stay, and once the job has taken it out the
    // record says so and the sidecar's roots file no longer names it. The
    // create's scan holds the catalog's lease for a moment, which the
    // removal waits out.
    const removal = await retryCatalogBusy(() =>
      app.api.delete('/libraries/{pid}', { path: { pid: libraryPid } }),
    );
    expect(removal.kind).toBe('remove-root');
    await expect
      .poll(
        async () => (await app.api.tryGet('/jobs/{pid}', { path: { pid: removal.pid } }))?.state,
        { timeout: T.fetch, message: 'the removal should run to done' },
      )
      .toBe('done');
    const listed = await app.api.get('/libraries');
    expect(listed.libraries.map((l) => l.pid)).not.toContain(libraryPid);
    await expect
      .poll(
        async () => {
          const removed = await app.api.tryGet('/admin/audit', {
            query: { action: 'library.remove', limit: 10 },
          });
          return (removed?.events ?? []).find((e) => e.targetPid === libraryPid)?.targetName;
        },
        { timeout: T.fetch, message: 'the removal should be on the record' },
      )
      .toBe('runtime');
    expect(await sidecarNames(), 'the sidecar file lets go of the root').not.toContain('runtime');
  } finally {
    await removeLibraryIfThere(app.api, libraryPid);
  }
});

// An account the administrator has granted no library imports a fixture
// track by name and by path, then shares what it built: both imports
// report the track missing, and a stranger holding the link streams
// nothing.
test('an account cannot publish a track it cannot see', async ({
  app,
  otherAccount,
  anonApi,
}) => {
  const items = await app.api.get('/library/items', { query: { mediaType: 'music', limit: 5 } });
  const track = (items.items ?? []).find((i) => i.artist && i.title);
  expect(track, 'the fixture library should hold named music').toBeTruthy();
  const source = await app.seed.createPlaylist('Path source', [track!.pid]);
  const m3u = await app.api.raw.get('/playlists/{pid}/m3u', { path: { pid: source } });
  const doc = await m3u.text();
  expect(doc).toContain('#EXTINF');

  const blind = await otherAccount('blind');
  const { user } = await app.api.as(blind.token).get('/auth/session');
  await app.api.patch('/users/{userId}', {
    path: { userId: user!.id },
    data: { libraryAccess: { mode: 'granted', libraryPids: [] } },
  });
  const theirs = app.api.as(blind.token);
  const byName = await theirs.post('/playlists/import', {
    data: { source: 'text', payload: `${track!.artist} - ${track!.title}` },
  });
  expect(byName.resolved).toBe(0);
  const byPath = await theirs.post('/playlists/m3u', { data: { name: 'Paths', content: doc } });
  expect(byPath.matched).toBe(0);

  const share = await theirs.post('/shares', {
    data: { pid: byPath.playlist.pid, allowDownload: false },
  });
  expect((await anonApi.raw.minted(`${share.url}/stream?i=0`)).status()).toBe(404);
});

// A content rule closes what an account may publish and what its links
// already serve: an allow rule naming a tag no track carries hides the
// whole library from it, so its album share is refused and the link it
// minted before the rule stops playing.
test('a content rule stops an album share and silences the earlier link', async ({
  app,
  otherAccount,
  anonApi,
}) => {
  const items = await app.api.get('/library/items', { query: { mediaType: 'music', limit: 5 } });
  const album = (items.items ?? []).find((i) => i.albumPid)?.albumPid;
  expect(album, 'the fixture library should hold an album').toBeTruthy();

  const kid = await otherAccount('kid');
  const { user } = await app.api.as(kid.token).get('/auth/session');
  const userId = user!.id;
  const account = await app.api.get('/users/{userId}', { path: { userId } });
  // Levelled first: a previous run against this stack left the rule on.
  await app.api.patch('/users/{userId}', {
    path: { userId },
    data: { permissions: { ...account.permissions!, tagAllow: [] } },
  });
  const theirs = app.api.as(kid.token);
  const early = await theirs.post('/shares', { data: { pid: album!, allowDownload: false } });

  await app.api.patch('/users/{userId}', {
    path: { userId },
    data: { permissions: { ...account.permissions!, tagAllow: [{ key: 'E2EKIDSAFE' }] } },
  });
  const refused = await theirs.raw.post('/shares', { data: { pid: album!, allowDownload: false } });
  expect(refused.status()).toBe(404);
  expect((await anonApi.raw.minted(`${early.url}/stream?i=0`)).status()).toBe(404);
});

// A deleted member's shared playlists go to the administrator who deletes
// the account, entries and all, and the record says how many went where.
test('deleting a member hands their shared playlist to the administrator', async ({
  app,
  otherAccount,
}) => {
  const member = await otherAccount('leaving');
  const theirs = app.api.as(member.token);
  const { user } = await theirs.get('/auth/session');
  const userId = user!.id;
  // The handover counts what the account holds, and an attempt that failed
  // before the delete left its playlists on it: clear them first.
  for (const owned of (await theirs.get('/playlists')).playlists ?? []) {
    if (owned.isOwner) {
      await theirs.delete('/playlists/{pid}', { path: { pid: owned.pid } });
    }
  }
  const items = await app.api.get('/library/items', { query: { mediaType: 'music', limit: 5 } });
  const pids = (items.items ?? []).slice(0, 2).map((i) => i.pid);
  expect(pids, 'the fixture library should hold music').toHaveLength(2);
  const shared = await theirs.post('/playlists', {
    data: { name: 'Handed over', kind: 'static', visibility: 'shared', itemPids: pids },
  });
  const private_ = await theirs.post('/playlists', {
    data: { name: 'Kept to themselves', kind: 'static', visibility: 'private', itemPids: pids },
  });

  await app.api.delete('/users/{userId}', { path: { userId } });
  try {
    const handed = await app.api.get('/playlists/{pid}', { path: { pid: shared.pid } });
    expect(handed.isOwner, 'the administrator owns it now').toBe(true);
    // Listed under the name the account goes by, its display name if it has one.
    const me = (await app.api.get('/auth/session')).user!;
    expect(handed.ownerName).toBe(me.displayName || me.username);
    expect(handed.visibility).toBe('shared');
    const entries = await app.api.get('/playlists/{pid}/items', { path: { pid: shared.pid } });
    expect(entries.entries.map((e) => e.item.pid), 'its entries are kept').toEqual(pids);
    const gone = await app.api.raw.get('/playlists/{pid}', { path: { pid: private_.pid } });
    expect(gone.status(), 'a private playlist went with its owner').toBe(404);

    const audit = await app.api.get('/admin/audit', {
      query: { action: 'user.delete', targetPid: userId },
    });
    expect(audit.events).toHaveLength(1);
    expect(audit.events[0].detail).toMatchObject({
      playlistsTransferred: 1,
      transferredTo: app.account.username,
    });
  } finally {
    // It is the administrator's now, and this account is reused.
    await app.api.raw.delete('/playlists/{pid}', { path: { pid: shared.pid } });
  }
});

// Disabling or deleting an account closes the sockets its devices hold,
// at once and with 4401, rather than leaving them hearing invalidations
// and driving the player until they happen to reconnect.
test('disabling or deleting an account closes its sockets', async ({ app, otherAccount, device }) => {
  for (const verb of ['disable', 'delete'] as const) {
    const listener = await otherAccount(`socket-${verb}`);
    const { user } = await app.api.as(listener.token).get('/auth/session');
    const userId = user!.id;
    const theirs = await device({ as: listener });
    await theirs.nav.enter('home');
    const closed = await theirs.auth.openSocketProbe();
    try {
      if (verb === 'disable') {
        await app.api.patch('/users/{userId}', { path: { userId }, data: { disabled: true } });
      } else {
        await app.api.delete('/users/{userId}', { path: { userId } });
      }
      expect(await closed(), `the socket after the ${verb}`).toBe(4401);
    } finally {
      // A disabled account cannot sign in, so the next run on this stack
      // could not mint it again.
      if (verb === 'disable') {
        await app.api.patch('/users/{userId}', { path: { userId }, data: { disabled: false } });
      }
    }
  }
});

// The download permission governs downloading: an account without it is
// refused download-info, a download URL it minted before stops, and its
// stream URL taken to the download route plays only the bytes its stream
// already gives (an original's, inline; a capped stream's, nothing).
// Disabling an account stops new opens of every URL it minted.
test('media URLs follow the account that minted them', async ({
  app,
  otherAccount,
  anonApi,
}) => {
  const { pid } = await app.seed.item('Alpha Song');
  const listener = await otherAccount('media');
  const { user } = await app.api.as(listener.token).get('/auth/session');
  const userId = user!.id;
  const account = await app.api.get('/users/{userId}', { path: { userId } });
  const theirs = app.api.as(listener.token);
  try {
    const download = (await theirs.get('/items/{pid}/download-info', { path: { pid } })).files[0].url;
    await app.api.patch('/users/{userId}', {
      path: { userId },
      data: { permissions: { ...account.permissions!, download: false } },
    });
    expect((await theirs.raw.get('/items/{pid}/download-info', { path: { pid } })).status()).toBe(403);
    expect((await anonApi.raw.minted(download)).status(), 'a download URL minted before').toBe(403);
    const playInfo = await theirs.get('/items/{pid}/play-info', { path: { pid } });
    const swapped = await anonApi.raw.minted(playInfo.url.replace('/media/stream?', '/media/download?'));
    expect(swapped.status(), 'the original stream on the download route').toBe(200);
    expect(swapped.headers()['content-disposition']).toMatch(/^inline/);
    const capped = await theirs.get('/items/{pid}/play-info', { path: { pid }, query: { maxBitrateKbps: 96 } });
    expect(capped.url, 'a capped stream').toContain('br=96');
    const cappedSwap = capped.url.replace('/media/stream?', '/media/download?');
    expect((await anonApi.raw.minted(cappedSwap)).status(), 'the capped stream on the download route').toBe(401);

    expect((await anonApi.raw.minted(playInfo.url)).status()).toBe(200);
    await app.api.patch('/users/{userId}', { path: { userId }, data: { disabled: true } });
    expect((await anonApi.raw.minted(playInfo.url)).status()).toBe(401);
  } finally {
    await app.api.patch('/users/{userId}', {
      path: { userId },
      data: { disabled: false, permissions: { ...account.permissions!, download: true } },
    });
  }
});
