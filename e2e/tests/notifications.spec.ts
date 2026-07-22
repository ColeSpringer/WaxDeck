import { test, expect } from '@playwright/test';
import { ensureAdmin, authed, startJsonSink } from './helpers';

// Notification delivery against the live stack: the administrator
// creates a server-scope webhook target pointed at a loopback sink,
// requests a per-target test, and the queued delivery arrives with the
// documented payload while the outcome lands on the target's health
// fields. Scoping, gating, and per-provider payloads are covered by
// the server's integration tests; this scenario pins the deployed
// path: API to outbox to worker tick to a real HTTP delivery.

test('a server-scope webhook target delivers a test end to end', async ({ request }) => {
  const token = await ensureAdmin(request);

  const events = await request.get('/api/v1/notifications/events', authed(token));
  expect(events.ok()).toBeTruthy();
  const catalog = (await events.json()).events as { name: string; scope: string }[];
  expect(catalog.some((e) => e.name === 'signup-requested' && e.scope === 'server')).toBeTruthy();
  expect(catalog.some((e) => e.name === 'test')).toBeFalsy();

  const sink = await startJsonSink();
  let pid = '';
  try {
    const created = await request.post('/api/v1/admin/notification-targets', {
      ...authed(token),
      data: {
        kind: 'webhook',
        label: 'e2e sink',
        config: { url: `${sink.url}/hook` },
        enabledEvents: ['backup-completed', 'backup-failed'],
      },
    });
    expect(created.status(), 'server-scope create is unguarded, loopback included').toBe(201);
    const target = await created.json();
    pid = target.pid as string;
    expect(pid).toMatch(/^nt-/);
    expect(target.config.url, 'config round-trips verbatim to the admin').toBe(`${sink.url}/hook`);

    const queued = await request.post(
      `/api/v1/admin/notification-targets/${pid}/test`,
      authed(token),
    );
    expect(queued.status()).toBe(202);

    // The outbox worker ticks every 5 seconds; the delivery must land
    // within a couple of ticks.
    await expect
      .poll(() => sink.received().length, {
        timeout: 15_000,
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
          const list = await request.get('/api/v1/admin/notification-targets', authed(token));
          if (!list.ok()) return 'unreadable';
          const row = ((await list.json()).targets as Record<string, unknown>[]).find(
            (t) => t.pid === pid,
          );
          if (!row) return 'missing';
          if (row.lastError) return `error: ${row.lastError}`;
          return row.lastSuccessAt ? 'delivered' : 'pending';
        },
        { timeout: 10_000, message: 'the health line should record the success' },
      )
      .toBe('delivered');
  } finally {
    if (pid) {
      await request.delete(`/api/v1/admin/notification-targets/${pid}`, authed(token));
    }
    await sink.close();
  }
});
