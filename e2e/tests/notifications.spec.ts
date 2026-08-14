import { test, expect } from './fixtures';
import { T } from './driver';
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

  try {
    await app.shell.notificationsBadged();
    // Waited for by what the row is about rather than off the top of
    // the list: the catalog is shared, so the news that badges the bell
    // first is not necessarily this test's own.
    const mine = await app.shell.openNotificationsUntil('upload');

    // And the row is a link, not a label.
    await mine.click();
    await app.nav.expectAt('uploads');

    // Clear empties the bell rather than only unbadging it. Walked
    // rather than re-entered: the list is what this client saw while it
    // was running, so a real page load would empty it first.
    await app.nav.to('home');
    await app.shell.openNotifications('upload');
    await app.shell.notificationsClear().click();
    await expect(app.shell.notificationRow('upload')).toBeHidden();
  } finally {
    await app.api.delete('/uploads/{uploadId}', {
      path: { uploadId: session.id },
    });
  }
});
