import { test, expect } from './fixtures';
import { App, J, T } from './driver';
import { SemanticsIds } from './semantics-ids';

// The catalog's own jobs and the health fixes, driven from the screens an
// administrator starts them on: followed in Tasks, told in the bell. A
// scan and an enrichment pass each hold a lease the whole stack shares,
// and a sweep request is server-wide, so this file is a project of its own
// in the chain and its tests run one after another.
test.describe.configure({ mode: 'serial' });

/// Waits until no catalog job runs: the previous project's runtime
/// library started a scan, and a second is refused while it holds the
/// lease.
async function catalogIdle(app: App): Promise<void> {
  await expect
    .poll(
      async () => {
        const list = await app.api.get('/jobs', { query: { limit: 50 } });
        return (list.jobs ?? []).filter((j) => j.state === 'running').map((j) => j.kind);
      },
      { timeout: T.fetch, message: 'no catalog job should be running' },
    )
    .toEqual([]);
}

/// Waits for the health worker's first sweep, which runs a minute after
/// the server starts: until then every count is zero.
async function sweptOnce(app: App): Promise<void> {
  await expect
    .poll(async () => (await app.api.get('/library/health')).warmingUp, {
      timeout: T.analyze,
      message: 'the first health sweep should have landed',
    })
    .toBe(false);
}

/// The inbox row this account was filed about a job or a task.
async function inboxRow(app: App, event: string, targetPid: string): Promise<string> {
  let id = '';
  await expect
    .poll(
      async () => {
        const page = await app.api.get('/users/me/notifications', { query: { limit: 100 } });
        id = page.notifications.find((n) => n.event === event && n.targetPid === targetPid)?.id ?? '';
        return id;
      },
      { timeout: T.fetch, message: `a ${event} row should reach the inbox` },
    )
    .not.toBe('');
  return id;
}

test('a scan started from the dashboard runs in Tasks and ends in the bell', async ({ app }) => {
  await catalogIdle(app);
  await app.nav.enter('admin');
  const started = app.page.waitForResponse(
    (r) => r.url().endsWith('/library/rescan') && r.request().method() === 'POST',
    { timeout: T.action },
  );
  await app.admin.control(SemanticsIds.adminAction('scan')).click();
  const job = (await (await started).json()) as { pid: string };
  expect(job.pid).toMatch(/^jb-/);

  // The toast offers where the scan is followed.
  await app.admin.control(SemanticsIds.openTasks).click();
  // Pushed over the screen it came from, as the other Tasks doors are,
  // so the address bar keeps that screen's location.
  await expect(app.admin.control(SemanticsIds.tasksScreen)).toBeVisible({ timeout: T.nav });
  const row = app.admin.control(SemanticsIds.jobRow(job.pid));
  await expect(row).toContainText('Library scan');
  await expect(row).toContainText('Done', { timeout: T.fetch });

  // The end is the starter's news, quietly: a bell row, no popup.
  const id = await inboxRow(app, 'job-finished', job.pid);
  await app.nav.to('home');
  await app.shell.openNotificationsUntil('job-finished', id);
});

test('a rule the server cannot fix says why, and one it can runs as a job', async ({ app }) => {
  test.setTimeout(J.long);
  await catalogIdle(app);
  await sweptOnce(app);
  // Read over the API, so the assertions follow what this stack holds: no
  // enrichment contact (genres wait on one), and the stub source run-stack
  // registers, which answers lyrics for one fixture title.
  const health = await app.api.get('/library/health');
  const blocked = health.rules.find((r) => r.fixBlocked !== undefined && r.failing > 0);
  expect(blocked, 'the stock stack should hold a failing rule it cannot fix').toBeTruthy();
  const lyrics = health.rules.find((r) => r.rule === 'missing-lyrics');
  expect(lyrics?.fixable, 'the stub source makes missing lyrics fixable').toBe(true);
  expect(lyrics?.failing ?? 0, 'the fixture tracks carry no lyrics').toBeGreaterThan(0);

  await app.nav.enter('health');
  await expect(app.admin.control(SemanticsIds.healthFixBlocked(blocked!.rule))).toBeVisible();
  await expect(app.admin.control(SemanticsIds.healthFix(blocked!.rule))).toHaveCount(0);

  // The stub alone, for the length of the fix: the fix is the catalog's
  // pass with lyrics forced, and every other source on the stack answers
  // from the internet. The order goes back as it was.
  const saved = (await app.api.get('/library/enrichment')).providers.map((p) => ({
    name: p.name,
    enabled: p.enabled ?? true,
  }));
  await app.api.put('/library/enrichment/sources', {
    data: { sources: saved.map((s) => ({ ...s, enabled: s.name === 'stubtapes-lyrics' })) },
  });
  try {
    const fixed = app.page.waitForResponse(
      (r) => r.url().endsWith('/library/health/fix') && r.request().method() === 'POST',
      { timeout: T.action },
    );
    await app.admin.control(SemanticsIds.healthFix('missing-lyrics')).click();
    const start = (await (await fixed).json()) as { jobPid?: string; queued: number };
    expect(start.jobPid).toMatch(/^jb-/);
    expect(start.queued).toBe(lyrics!.failing);

    await app.admin.control(SemanticsIds.openTasks).click();
    // Pushed over the screen it came from, as the other Tasks doors are,
    // so the address bar keeps that screen's location.
    await expect(app.admin.control(SemanticsIds.tasksScreen)).toBeVisible({ timeout: T.nav });
    const row = app.admin.control(SemanticsIds.jobRow(start.jobPid!));
    await expect(row).toContainText('Enrichment');
    await expect(row).toContainText('Done', { timeout: T.fetch });

    // The rule is re-checked for what the pass reached: the one title the
    // stub knows is filled, the rest still fail.
    await inboxRow(app, 'health-fix-finished', start.jobPid!);
    const after = await app.api.get('/library/health');
    expect(after.rules.find((r) => r.rule === 'missing-lyrics')?.failing).toBe(
      lyrics!.failing - 1,
    );
  } finally {
    await app.api.put('/library/enrichment/sources', { data: { sources: saved } });
  }
});

test('a sweep asked for reads as running until it lands, with no reload', async ({ app }) => {
  // The health worker ticks once a minute, so the request waits up to
  // that long before the sweep runs.
  test.setTimeout(J.long);
  await app.nav.enter('health');
  const sweep = app.admin.control(SemanticsIds.healthSweep);
  await sweep.click();
  await expect(sweep).toBeDisabled();
  await expect(sweep).toBeEnabled({ timeout: T.analyze });
  const health = await app.api.get('/library/health');
  expect(health.sweeping).toBe(false);
});
