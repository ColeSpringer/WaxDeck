import { test, expect } from './fixtures';
import { T } from './driver';
import { SemanticsIds } from './semantics-ids';
import { startJsonSink } from './support/json-sink';

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

  // The cheapest change that emits a marker: no bytes move.
  const session = await app.api.post('/uploads', {
    data: { fileName: 'bell.mp3', sizeBytes: 1024, mediaType: 'music' },
  });
  expect(session.id).toMatch(/^up-/);

  let second = '';
  try {
    await app.shell.notificationsBadged();
    // Waited for by what the row is about rather than off the top of
    // the list: the catalog is shared, so the news that badges the bell
    // first is not necessarily this test's own. At the fetch tier for
    // the same reason the badge is no longer the wait - this account
    // has a durable inbox, and a sibling's backup lights the badge
    // before this test's upload has walked in.
    const mine = await app.shell.openNotificationsUntil('upload', undefined, {
      within: T.fetch,
    });

    // And the row is a link, not a label.
    await mine.click();
    await app.nav.expectAt('uploads');

    // Arriving is what deals with it. The bell held its rows until one
    // was tapped or the whole list was emptied, so a badge stood over
    // work that had already been done.
    //
    // Read back from home, which is the one app bar the bell hangs in:
    // every screen draws its own chrome, so a row always sends you
    // somewhere that has none. Walked rather than re-entered, here and
    // below: the list is what this client saw while it was running, so
    // a real page load would empty it first and prove nothing.
    await app.nav.to('home');
    await app.shell.openNotificationsPanel();
    await expect(app.shell.notificationRow('upload')).toBeHidden();
    await app.shell.closeNotifications();

    // Reading still empties the bell, on a second piece of news this
    // test never opens.
    second = (
      await app.api.post('/uploads', {
        data: { fileName: 'bell-2.mp3', sizeBytes: 1024, mediaType: 'music' },
      })
    ).id;
    await app.shell.notificationsBadged();
    await app.shell.openNotificationsUntil('upload', undefined, {
      within: T.fetch,
    });
    // The bell's last row reads everything rather than deleting it: the
    // same gesture against a durable inbox would throw away ninety days
    // of history from a dropdown. The peek empties either way.
    await app.shell.notificationsPeekRead().click();
    await expect(app.shell.notificationRow('upload')).toBeHidden();
  } finally {
    for (const id of [session.id, second]) {
      if (id) await app.api.delete('/uploads/{uploadId}', { path: { uploadId: id } });
    }
  }
});

// The durable half: what happened to this account, kept server-side, so
// a device that was closed at the time still finds it.
test('the inbox keeps what happened, and reading it is a state', async ({ app }) => {
  // A backup is the cheapest server-scope event to cause, and every
  // enabled administrator gets a row for it - siblings included, which
  // is why nothing here counts rows. The subject is this test's own.
  const before = new Date().toISOString();
  const started = await app.api.raw.post('/admin/backups');
  expect([202, 409]).toContain(started.status());

  type Row = { id: string; event: string; createdAt: string; readAt?: string };
  const mine = async (): Promise<Row | undefined> => {
    const page = await app.api.tryGet('/users/me/notifications', { query: { limit: 200 } });
    return (page?.notifications ?? []).find(
      (n) => n.event === 'backup-completed' && n.createdAt > before,
    );
  };

  await expect
    .poll(async () => (await mine()) !== undefined, {
      timeout: T.fetch,
      message: 'the finished backup should file itself in the inbox',
    })
    .toBe(true);
  const row = (await mine())!;
  expect(row.id).toMatch(/^nf-/);
  expect(row.readAt, 'a row nobody has looked at is unread').toBeUndefined();

  const unread = await app.api.get('/users/me/notifications');
  expect(unread.unreadCount).toBeGreaterThanOrEqual(1);

  // The bell says so, and the screen lists it - after a real page load,
  // which is what the session-local half could never survive.
  await app.nav.enter('home');
  await app.shell.notificationsBadged();
  await app.nav.enter('notifications');
  // By the row's own id: the inbox keeps ninety days, so two backups
  // are two rows and the event alone names neither.
  await expect(app.shell.notificationRow('backup-completed', row.id)).toBeVisible();

  // Reading is a state, not a disappearance: the row stays listed.
  await app.settings.control(SemanticsIds.notificationsMarkAllRead).click();
  await expect
    .poll(async () => (await mine())?.readAt !== undefined, {
      timeout: T.assert,
      message: 'mark all read should reach the server',
    })
    .toBe(true);
  await expect(app.shell.notificationRow('backup-completed', row.id)).toBeVisible();

  // Delete is what removes it, and it stays removed across a reload.
  await app.settings.control(SemanticsIds.notificationDelete(row.id)).click();
  await expect
    .poll(async () => (await mine()) === undefined, {
      timeout: T.assert,
      message: 'the deleted row should be gone from the server',
    })
    .toBe(true);
  await app.nav.enter('notifications');
  await expect(app.shell.notificationRow('backup-completed', row.id)).toBeHidden();
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
