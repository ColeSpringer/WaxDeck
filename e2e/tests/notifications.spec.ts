import { test, expect, type SpecPage } from './fixtures';
import { App, T, pressOnce, retryCatalogBusy } from './driver';
import { SemanticsIds } from './semantics-ids';
import { startJsonSink } from './support/json-sink';
import type { components } from './api-types';

type ServerSyncPage = components['schemas']['ServerSyncPage'];

// Notification delivery against the live stack. Scoping, gating and
// per-provider payloads are the server's integration tests; this pins
// the deployed path: API to outbox to worker tick to real HTTP.

test('a server-scope webhook target delivers a test end to end', async ({ app }) => {
  const catalog = (await app.api.get('/notifications/events')).events ?? [];
  expect(
    catalog.some((e) => e.name === 'signup-requested' && e.scope === 'server'),
  ).toBeTruthy();
  expect(catalog.some((e) => e.name === 'test')).toBeFalsy();

  const sink = await startJsonSink();
  let pid = '';
  try {
    // Deleted in the `finally`: a target is server-global, so it would
    // outlive the run pointing at a loopback port that is gone.
    const target = await app.api.post('/admin/notification-targets', {
      data: {
        kind: 'webhook',
        label: 'e2e sink',
        config: { url: `${sink.url}/hook` },
        enabledEvents: ['backup-completed', 'backup-failed'],
        muted: false,
        minIntervalSeconds: 0,
      },
    });
    pid = target.pid;
    expect(pid).toMatch(/^nt-/);
    expect(target.config?.url, 'config round-trips verbatim to the admin').toBe(
      `${sink.url}/hook`,
    );

    const queued = await app.api.raw.post('/admin/notification-targets/{targetId}/test', {
      path: { targetId: pid },
    });
    expect(queued.status()).toBe(202);

    // The outbox worker ticks every 5 seconds; the delivery must land
    // within a couple of ticks.
    await expect
      .poll(() => sink.received().length, {
        message: 'the queued test should reach the sink within the outbox tick',
      })
      .toBeGreaterThanOrEqual(1);
    const delivery = sink.received()[0] as Record<string, string>;
    expect(delivery.event).toBe('test');
    expect(delivery.title).toBe('WaxDeck test notification');
    expect(delivery.body).toContain('per-target test');
    expect(Date.parse(delivery.timestamp), 'timestamp is RFC 3339').not.toBeNaN();

    // The outcome is observable where the settings surface polls it.
    await expect
      .poll(
        async () => {
          const list = await app.api.tryGet('/admin/notification-targets');
          if (list === undefined) return 'unreadable';
          const row = (list.targets ?? []).find((t) => t.pid === pid);
          if (!row) return 'missing';
          if (row.lastError) return `error: ${row.lastError}`;
          return row.lastSuccessAt ? 'delivered' : 'pending';
        },
        { timeout: T.assert, message: 'the health line should record the success' },
      )
      .toBe('delivered');
  } finally {
    if (pid) {
      await app.api.delete('/admin/notification-targets/{targetId}', {
        path: { targetId: pid },
      });
    }
    await sink.close();
  }
});

// The bell: the in-app half of the same news. Web has no sync engine, so
// this exercises notifications_binder's puller end to end.

/// The client walking its server stream past a `notification` marker. Armed
/// before the change that emits one, because the walk can outrun the
/// request's own answer.
function walkedPastNotification(page: SpecPage) {
  const walked = page.waitForResponse(
    async (r) => {
      if (!r.url().includes('/sync/server') || !r.url().includes('since=')) return false;
      const body = (await r.json().catch(() => undefined)) as ServerSyncPage | undefined;
      return (body?.events ?? []).some((e) => e.kind === 'notification');
    },
    { timeout: T.fetch },
  );
  // Marked handled, so a run that has already failed is not reported
  // twice; the caller's own awaits still throw.
  walked.catch(() => {});
  return walked;
}

type InboxRow = components['schemas']['Notification'];

/// This account's row for [event] that took an occurrence after [since]. A
/// folding event keeps one row, so a second occurrence is the same id with
/// a later `updatedAt`, and `createdAt` says nothing about it.
async function rowSince(app: App, event: string, since: string): Promise<InboxRow | undefined> {
  const page = await app.api.tryGet('/users/me/notifications', { query: { limit: 200 } });
  // As instants: the server trims trailing zeros, so two stamps in one
  // second do not order as strings.
  return (page?.notifications ?? []).find(
    (n) => n.event === event && Date.parse(n.updatedAt) > Date.parse(since),
  );
}

/// One backup, started and waited into this account's inbox: the cheapest
/// event that files an announcement the bell draws. A sibling's backup may
/// hold the slot (409); its occurrence reaches this account's row all the
/// same.
async function backedUp(app: App): Promise<InboxRow> {
  const since = new Date().toISOString();
  const started = await app.api.raw.post('/admin/backups');
  expect([202, 409]).toContain(started.status());
  await expect
    .poll(async () => (await rowSince(app, 'backup-completed', since)) !== undefined, {
      timeout: T.fetch,
      message: 'the finished backup should file itself in the inbox',
    })
    .toBe(true);
  return (await rowSince(app, 'backup-completed', since))!;
}

test('the bell reports what happened while the app was open', async ({
  app,
  page,
}) => {
  // The client draws "while the app was open" itself, minting a cursor
  // on the way up and reporting nothing from before it. Armed ahead of
  // the navigation that causes it, or it may already have been served.
  const minted = page.waitForResponse(
    (r) => r.url().includes('/sync/server') && !r.url().includes('since='),
    { timeout: T.nav },
  );
  await app.nav.enter('home');
  await expect(app.shell.notificationsBell()).toBeVisible();
  await minted;

  const walked = walkedPastNotification(page);
  const first = await backedUp(app);
  // The walk, not the badge, which a sibling's backup can light first: a
  // bell opened before the walk lacks this news, and the soak's re-opens
  // then collided two clicks on a menu that stamped it seen as it opened.
  await walked;
  await app.shell.notificationsBadged();
  const mine = await app.shell.openNotificationsUntil('backup-completed', first.id);

  // And the row is a link, not a label.
  await mine.click();
  await app.nav.expectAt('adminBackups');

  // Arriving is what deals with it: the router marks it read by event, so
  // a badge does not stand over work that has been looked at. Read back
  // from home, which is the one app bar the bell hangs in. Walked rather
  // than re-entered, here and below: a real page load would empty the
  // list this client saw while it ran and prove nothing.
  await app.nav.to('home');
  await app.shell.openNotificationsPanel();
  await expect(app.shell.notificationRow('backup-completed', first.id)).toBeHidden();
  await app.shell.closeNotifications();

  // A second backup folds into the same row: one id, unread again, risen
  // to the top. Reading still empties the bell, on news this test never
  // opens.
  const walkedAgain = walkedPastNotification(page);
  const second = await backedUp(app);
  expect(second.id, 'a folding event keeps one row').toBe(first.id);
  expect(Date.parse(second.updatedAt)).toBeGreaterThan(Date.parse(first.updatedAt));
  await walkedAgain;
  await app.shell.notificationsBadged();
  await app.shell.openNotificationsUntil('backup-completed', first.id);
  // The bell's last row reads everything rather than deleting it: the
  // same gesture against a durable inbox would throw away ninety days
  // of history from a dropdown. The peek empties either way.
  await app.shell.notificationsPeekRead().click();
  // Reopened, because the click closes the menu whatever it read.
  await app.shell.openNotificationsPanel();
  await expect(app.shell.notificationRow('backup-completed', first.id)).toBeHidden();
  await app.shell.closeNotifications();
});

// The durable half: what happened to this account, kept server-side, so
// a device that was closed at the time still finds it.
test('the inbox keeps what happened, and reading it is a state', async ({ app }) => {
  // A backup is the cheapest server-scope event to cause, and every
  // enabled administrator gets a row for it - siblings included, which
  // is why nothing here counts rows. The subject is this test's own: the
  // row this occurrence landed in.
  const before = new Date().toISOString();
  const started = await app.api.raw.post('/admin/backups');
  expect([202, 409]).toContain(started.status());

  // By `updatedAt`: backups fold into one row per account, so a row that
  // already existed takes this occurrence under its old `createdAt`.
  const mine = (): Promise<InboxRow | undefined> => rowSince(app, 'backup-completed', before);

  await expect
    .poll(async () => (await mine()) !== undefined, {
      timeout: T.fetch,
      message: 'the finished backup should file itself in the inbox',
    })
    .toBe(true);
  const row = (await mine())!;
  // The row itself from here on: a later backup folds into it, or opens a
  // new one once this is gone, and neither is this row.
  const same = async (): Promise<InboxRow | undefined> =>
    (
      (await app.api.tryGet('/users/me/notifications', { query: { limit: 200 } }))?.notifications ?? []
    ).find((n) => n.id === row.id);
  expect(row.id).toMatch(/^nf-/);
  expect(row.readAt, 'an occurrence nobody has looked at is unread').toBeUndefined();

  const unread = await app.api.get('/users/me/notifications');
  expect(unread.unreadCount).toBeGreaterThanOrEqual(1);

  // The bell says so, and the screen lists it - after a real page load,
  // which is what the session-local half could never survive.
  await app.nav.enter('home');
  await app.shell.notificationsBadged();
  await app.nav.enter('notifications');
  // By the row's own id, which a folded occurrence keeps.
  await expect(app.shell.notificationRow('backup-completed', row.id)).toBeVisible();

  // Reading is a state, not a disappearance: the row stays listed.
  await app.settings.control(SemanticsIds.notificationsMarkAllRead).click();
  await expect
    .poll(async () => (await same())?.readAt !== undefined, {
      timeout: T.assert,
      message: 'mark all read should reach the server',
    })
    .toBe(true);
  await expect(app.shell.notificationRow('backup-completed', row.id)).toBeVisible();

  // Delete is what removes it, and it stays removed across a reload.
  await app.settings.control(SemanticsIds.notificationDelete(row.id)).click();
  await expect
    .poll(async () => (await same()) === undefined, {
      timeout: T.assert,
      message: 'the deleted row should be gone from the server',
    })
    .toBe(true);
  await app.nav.enter('notifications');
  await expect(app.shell.notificationRow('backup-completed', row.id)).toBeHidden();
});

// One URL is one thing to tell the account about, however many entries it
// enumerates, and a queue that has been answered is not a door any more.
//
// An uploader rather than an administrator: an administrator's review scope
// is the whole shared queue, so nothing exact could be said about its count
// or about when it empties. An uploader's is its own entries. The account
// outlives a run on a reused stack, so the case starts by emptying what an
// earlier one left (entries waiting, an inbox with a resolved row) and then
// counts whatever the stub's entries come to rather than a fixed number: how
// many of them reach review depends on what the library already holds.
test('one URL acquisition leaves one review row, and an answered queue stops opening', async ({
  app,
  otherAccount,
  device,
}) => {
  const uploader = await otherAccount('uploader');
  const theirApi = app.api.as(uploader.token);
  const me = await theirApi.get('/auth/session');
  await app.api.patch('/users/{userId}', {
    path: { userId: me.user!.id },
    data: { uploadEnabled: true },
  });

  const pending = async () =>
    (await theirApi.get('/review/queue', { query: { status: 'pending', limit: 200 } })).entries ?? [];
  const decideAll = async () => {
    for (const entry of await pending()) {
      await retryCatalogBusy(() =>
        theirApi.post('/review/queue/{entryId}/decide', {
          path: { entryId: entry.id },
          data: { action: 'as-is' },
        }),
      );
    }
  };
  const inboxRows = async (): Promise<InboxRow[]> =>
    (await theirApi.get('/users/me/notifications', { query: { limit: 200 } })).notifications ?? [];
  const reviewRows = async (): Promise<InboxRow[]> =>
    (await inboxRows()).filter((n) => n.event === 'review-ready');

  // A clean start: nothing identifying, nothing waiting, no row.
  await expect
    .poll(async () => (await pending()).some((e) => e.identifying), {
      timeout: T.fetch,
      message: 'an earlier run left entries still identifying',
    })
    .toBe(false);
  await decideAll();
  await expect
    .poll(async () => (await pending()).length, {
      timeout: T.fetch,
      message: 'the leftover entries should all be decided',
    })
    .toBe(0);
  await theirApi.delete('/users/me/notifications');
  await expect
    .poll(async () => (await inboxRows()).length, {
      timeout: T.fetch,
      message: 'the inbox should be empty before the acquisition',
    })
    .toBe(0);

  const task = await theirApi.post('/acquisitions', {
    data: { url: 'http://127.0.0.1:4422/playlist', mediaType: 'music' },
  });
  expect(task.id).toMatch(/^tk-/);
  await expect
    .poll(async () => (await theirApi.get('/tools/tasks/{taskId}', { path: { taskId: task.id } })).state, {
      timeout: T.fetch,
      message: 'the acquisition should run to done',
    })
    .toBe('done');

  // However many entries it enumerates, one row in the whole inbox, whatever
  // its kind, counting the ones waiting: recomputed from the queue, so it
  // settles once none is still identifying.
  await expect
    .poll(
      async () => {
        const waiting = await pending();
        if (waiting.some((e) => e.identifying)) return 'entries still identifying';
        if (waiting.length === 0) return 'no entry reached review';
        const all = await inboxRows();
        if (all.length !== 1) return `${all.length} inbox rows: ${all.map((n) => n.event).join(', ')}`;
        const rows = await reviewRows();
        if (rows.length !== 1) return `${rows.length} review rows`;
        if (rows[0].resolvedAt !== undefined) return 'the row resolved with entries waiting';
        return rows[0].count === waiting.length
          ? 'one row, counted'
          : `row counts ${rows[0].count}, ${waiting.length} waiting`;
      },
      {
        timeout: T.fetch,
        message: 'the entries should reach the inbox as one row that counts the ones waiting',
      },
    )
    .toBe('one row, counted');
  const row = (await reviewRows())[0];

  const theirs = await device({ as: uploader });
  await theirs.nav.enter('notifications');
  const door = theirs.shell.notificationRow('review-ready', row.id);
  await expect(door).toBeVisible({ timeout: T.fetch });
  // The control: while entries wait the row is a door.
  await door.click();
  await theirs.nav.expectAt('review');

  // Decided, the queue is answered and the row resolves.
  await decideAll();
  await expect
    .poll(async () => (await reviewRows())[0]?.resolvedAt !== undefined, {
      timeout: T.fetch,
      message: 'the row should resolve once nothing waits',
    })
    .toBe(true);
  expect(await reviewRows(), 'still the one row').toHaveLength(1);

  // Resolved, the row is listed and can be deleted, and it opens nowhere.
  // The address is held for a second before it is read, so a navigation
  // that lands late is not missed by a check made at once.
  await theirs.nav.enter('notifications');
  const resolved = theirs.shell.notificationRow('review-ready', row.id);
  await expect(resolved).toBeVisible({ timeout: T.fetch });
  await pressOnce(resolved);
  await theirs.nav.settledAt('notifications');
  await expect(theirs.settings.control(SemanticsIds.notificationDelete(row.id))).toBeVisible();
});

// The two ways a destination is turned down without being deleted, and
// the signing that lets a receiver tell a real delivery from a forged
// one. Server-scope targets, because they are the ones the sink can be
// pointed at without the private-host guard.
test('a signed webhook proves itself, and a muted one stays quiet', async ({
  app,
}) => {
  const sink = await startJsonSink();
  const pids: string[] = [];
  try {
    const signed = await app.api.post('/admin/notification-targets', {
      data: {
        kind: 'webhook',
        label: 'e2e signed sink',
        config: {
          url: `${sink.url}/signed`,
          headers: { 'X-Routing-Key': 'e2e' },
          secret: 'e2e-secret',
        },
        enabledEvents: ['backup-completed'],
        muted: false,
        minIntervalSeconds: 0,
      },
    });
    pids.push(signed.pid);
    expect(signed.muted, 'a target is live unless it says otherwise').toBe(false);

    const muted = await app.api.post('/admin/notification-targets', {
      data: {
        kind: 'webhook',
        label: 'e2e muted sink',
        config: { url: `${sink.url}/muted` },
        enabledEvents: ['backup-completed'],
        muted: true,
        minIntervalSeconds: 0,
      },
    });
    pids.push(muted.pid);
    expect(muted.muted).toBe(true);

    // A test bypasses the event selection and the mute alike: it is how
    // somebody checks a destination they have just silenced.
    for (const pid of pids) {
      const queued = await app.api.raw.post('/admin/notification-targets/{targetId}/test', {
        path: { targetId: pid },
      });
      expect(queued.status()).toBe(202);
    }
    await expect
      .poll(() => sink.deliveries().length, {
        message: 'both tests should reach the sink within a couple of ticks',
      })
      .toBeGreaterThanOrEqual(2);

    const delivery = sink.deliveries().find((d) => d.headers['x-waxdeck-signature']);
    expect(delivery, 'the signed target carries its headers').toBeTruthy();
    expect(delivery!.headers['x-routing-key']).toBe('e2e');
    const stamp = delivery!.headers['x-waxdeck-timestamp'];
    expect(Number(stamp)).toBeGreaterThan(0);
    // The receiver's side of the documented recipe, over the exact
    // bytes that arrived.
    const { createHmac } = await import('node:crypto');
    const want =
      'sha256=' +
      createHmac('sha256', 'e2e-secret').update(`${stamp}.${delivery!.raw}`).digest('hex');
    expect(delivery!.headers['x-waxdeck-signature']).toBe(want);
    // The muted one delivered its test and nothing else.
    expect(sink.deliveries().some((d) => !d.headers['x-waxdeck-signature'])).toBe(true);
  } finally {
    for (const pid of pids) {
      await app.api.delete('/admin/notification-targets/{targetId}', {
        path: { targetId: pid },
      });
    }
    await sink.close();
  }
});
