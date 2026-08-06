import { test, expect } from './fixtures';
import { T } from './driver';
import { startJsonSink } from './support/json-sink';

// Notification delivery against the live stack: the administrator
// creates a server-scope webhook target pointed at a loopback sink,
// requests a per-target test, and the queued delivery arrives with the
// documented payload while the outcome lands on the target's health
// fields. Scoping, gating, and per-provider payloads are covered by
// the server's integration tests; this scenario pins the deployed
// path: API to outbox to worker tick to a real HTTP delivery.

test('a server-scope webhook target delivers a test end to end', async ({ app }) => {
  const catalog = (await app.api.get('/notifications/events')).events ?? [];
  expect(
    catalog.some((e) => e.name === 'signup-requested' && e.scope === 'server'),
  ).toBeTruthy();
  expect(catalog.some((e) => e.name === 'test')).toBeFalsy();

  const sink = await startJsonSink();
  let pid = '';
  try {
    // Deleted in the `finally` rather than reused by label: a
    // notification target is server-global, so unlike this account's own
    // playlists it would outlive the run for every other administrator
    // as well - and it points at a loopback port that will not exist by
    // then.
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
