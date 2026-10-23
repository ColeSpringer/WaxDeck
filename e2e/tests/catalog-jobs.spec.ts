import type { Locator, Request } from '@playwright/test';
import { test, expect } from './fixtures';
import { App, J, T, clickUntilRequested, retryCatalogBusy } from './driver';
import { clickThrough, typeInto, wheelIntoReach, wheelIntoView } from './driver/gestures';
import type { components } from './api-types';
import { SemanticsIds } from './semantics-ids';

type OrganizeReport = components['schemas']['OrganizeReport'];

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

test('a scan started from the dashboard runs in Tasks and ends in the bell', async ({
  app,
  otherAccount,
}) => {
  await catalogIdle(app);
  await app.nav.enter('admin');
  const isRescan = (r: Request) =>
    r.url().endsWith('/library/rescan') && r.method() === 'POST';
  // Outlasts the click's own retries, which run to T.nav.
  const started = app.page.waitForResponse((r) => isRescan(r.request()), {
    timeout: T.fetch,
  });
  // The request is the only sign the press landed, and a canvas press
  // can be swallowed while the dashboard is still settling.
  await clickUntilRequested(
    app.page,
    app.admin.control(SemanticsIds.adminAction('scan')),
    isRescan,
  );
  const job = (await (await started).json()) as { pid: string };
  expect(job.pid).toMatch(/^jb-/);
  // The toast offers where the scan is followed. Not taken: news is
  // read when it arrives where its row points, and a scan this small
  // ends before Tasks has drawn, so the bell is read first.
  await expect(app.admin.control(SemanticsIds.openTasks)).toBeVisible({ timeout: T.step });
  // A job is read by the audience that hears of it, which a plain
  // account is not.
  const bystander = await otherAccount('bystander');
  const read = await app.api.as(bystander.token).raw.get('/jobs/{pid}', { path: { pid: job.pid } });
  expect(read.status()).toBe(403);

  await expect
    .poll(async () => (await app.api.get('/jobs/{pid}', { path: { pid: job.pid } })).state, {
      timeout: T.fetch,
      message: 'the scan should run to done',
    })
    .toBe('done');
  // Its counts partition what it saw, whatever the shared library holds:
  // every audio file was added, updated, a sidecar change, a copy,
  // unchanged or errored, and every file was audio or skipped.
  const finished = await app.api.get('/jobs/{pid}', { path: { pid: job.pid } });
  const n = (finished.result ?? {}) as Record<string, number>;
  expect(n.audioFiles).toBe(
    n.created + n.updated + n.sidecarsUpdated + n.copies + n.unchanged + n.errored,
  );
  expect(n.filesSeen).toBe(n.audioFiles + n.skipped);

  // The end is the starter's news, quietly: a bell row, no popup. The
  // row leads to Tasks, which says what the scan found.
  const id = await inboxRow(app, 'job-finished', job.pid);
  await app.nav.to('home');
  const news = await app.shell.openNotificationsUntil('job-finished', id);
  await news.click();
  await expect(app.admin.control(SemanticsIds.tasksScreen)).toBeVisible({ timeout: T.nav });
  const row = app.admin.control(SemanticsIds.jobRow(job.pid));
  await expect(row).toContainText('Library scan');
  await expect(row).toContainText('Done');
  await expect(row).toContainText(`copies ${n.copies}`, { timeout: T.fetch });
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
    const isFix = (r: Request) =>
      r.url().endsWith('/library/health/fix') && r.method() === 'POST';
    const fixed = app.page.waitForResponse((r) => isFix(r.request()), {
      timeout: T.fetch,
    });
    await clickUntilRequested(
      app.page,
      app.admin.control(SemanticsIds.healthFix('missing-lyrics')),
      isFix,
    );
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

test('the quality upgrades section answers once the library is analyzed', async ({ app }) => {
  test.setTimeout(J.long);
  await catalogIdle(app);
  // Analysis fingerprints every file, which the groups across items
  // read. A sibling worker may hold the lease; a started pass is waited
  // to done.
  const started = await app.api.raw.post('/library/analyze');
  expect([202, 409]).toContain(started.status());
  if (started.status() === 202) {
    const job = (await started.json()) as { pid: string };
    await expect
      .poll(async () => (await app.api.get('/jobs/{pid}', { path: { pid: job.pid } })).state, {
        timeout: T.analyze,
        message: 'the analyze pass should run to done',
      })
      .toBe('done');
  }

  // The section reads its listing and draws what came back. The stack
  // is shared, so nothing is resolved.
  const isListing = (r: Request) =>
    r.url().endsWith('/library/upgrades') && r.method() === 'GET';
  const listed = app.page.waitForResponse((r) => isListing(r.request()), { timeout: T.fetch });
  await app.nav.enter('health');
  expect((await listed).status(), 'the upgrades listing should answer').toBe(200);
  const groups = (await app.api.get('/library/upgrades')).groups;
  if (groups.length > 0) {
    await expect(
      app.admin.control(
        SemanticsIds.upgradeGroup(groups[0].members.map((m) => m.filePid).join('+')),
      ),
    ).toBeVisible({ timeout: T.fetch });
  }
});

/// Runs a kind change through the API to done.
async function kindChanged(app: App, pids: string[], mediaType: 'music' | 'audiobook'): Promise<void> {
  const job = await retryCatalogBusy(() =>
    app.api.post('/items/kind', { data: { pids, mediaType, writeBack: false } }),
  );
  await expect
    .poll(async () => (await app.api.get('/jobs/{pid}', { path: { pid: job.pid } })).state, {
      timeout: T.fetch,
      message: 'the kind change should run to done',
    })
    .toBe('done');
}

test('an album the library reads as music becomes one audiobook', async ({ app }) => {
  test.setTimeout(J.long);
  await catalogIdle(app);
  const firstLecture = async () =>
    (await app.api.get('/library/items', { query: { mediaType: 'music', limit: 500 } })).items.find(
      (i) => i.title === 'First Lecture',
    );
  // A kept stack holds the book an earlier run made; put it back first.
  let first = await firstLecture();
  if (first === undefined) {
    const book = (
      await app.api.get('/library/items', { query: { mediaType: 'audiobook', limit: 500 } })
    ).items.find((i) => i.title === 'The Misfiled Lectures');
    expect(book, 'the misfiled lectures should be in the library, as music or as a book').toBeDefined();
    await kindChanged(app, [book!.pid], 'music');
    first = await firstLecture();
  }
  expect(first?.albumPid, 'the lectures should sit on an album').toBeTruthy();

  // The overflow draws before the album's tracks arrive, and a menu
  // opened then holds no change of kind, nor gains one while it stays
  // open: the first track row says the album is in.
  await app.nav.open(`/music/albums/${first!.albumPid}`, app.music.control(SemanticsIds.albumTrackMore(0)));
  // A pass a schedule started may hold the catalog when Confirm lands:
  // the dialog then closes on catalog-busy, and the change is asked for
  // again once the catalog is free.
  const isKindPost = (r: Request) => r.url().endsWith('/items/kind') && r.method() === 'POST';
  for (let attempt = 1; ; attempt++) {
    await clickThrough(app.music.entityOverflow(), app.music.control(SemanticsIds.itemMenuKindAlbum));
    await clickThrough(
      app.music.control(SemanticsIds.itemMenuKindAlbum),
      app.music.control(SemanticsIds.kindConfirm),
    );
    const posted = app.page.waitForResponse((r) => isKindPost(r.request()), { timeout: T.fetch });
    await clickUntilRequested(app.page, app.music.control(SemanticsIds.kindConfirm), isKindPost);
    if ((await posted).status() !== 409 || attempt === 3) break;
    await catalogIdle(app);
  }
  // The dialog follows the job and opens what the album became.
  await expect(app.books.resume()).toBeVisible({ timeout: T.fetch });
  const bookPid = `bk-${first!.pid.slice(3)}`;
  const detail = await app.api.get('/books/{pid}', { path: { pid: bookPid } });
  expect(detail.parts, 'both lectures should be the book').toHaveLength(2);

  // Leave the library as the other specs expect it.
  await kindChanged(app, [bookPid], 'music');
});

/// Opens a typed-word confirmation from [trigger], confirms it, and answers
/// the accepted report. The library watcher scans what a run moved about
/// ten seconds later, so a confirm can land while that scan holds the
/// file-mutation scope: the dialog then closes on catalog-busy, and the
/// action is asked for again once the catalog is free.
async function confirmTyped(
  app: App,
  trigger: Locator,
  word: string,
  confirm: string,
  isAction: (r: Request) => boolean,
): Promise<OrganizeReport> {
  const page = app.page;
  const field = app.admin.control(SemanticsIds.confirmField);
  const height = page.viewportSize()?.height ?? (await page.evaluate(() => window.innerHeight));
  for (let attempt = 1; ; attempt++) {
    // Under a report's held files, a history row sits screens past the
    // fold, further than a notch per try covers in time: one wheel takes
    // it most of the way, and the fine one lands it.
    const box = await trigger.boundingBox({ timeout: T.nav });
    const off = box === null ? 0 : box.y + box.height / 2 - height / 2;
    if (Math.abs(off) > height) await wheelIntoView(page, trigger, { by: off });
    await wheelIntoReach(page, trigger);
    await clickThrough(trigger, field);
    await typeInto(page, field, word);
    const answered = page.waitForResponse((r) => isAction(r.request()), { timeout: T.fetch });
    await clickUntilRequested(page, app.admin.control(confirm), isAction);
    const response = await answered;
    // The status first: a body that is not JSON would hide it.
    if (response.status() === 409 && (await response.json()).code === 'catalog-busy' && attempt < 3) {
      await catalogIdle(app);
      continue;
    }
    expect(response.status(), `the ${word} confirm should be accepted`).toBe(200);
    return (await response.json()) as OrganizeReport;
  }
}

// The path rule's bulk fix is an organize pass: Health opens Organize with
// the dry run under way, the apply asks for the typed word, and the run is
// in the history, whose undo puts every file back. Asserted on the whole
// library's dry run and on items this test picks from it, which nothing
// else moves while this serial project runs.
test('the path rule previews from Organize, applies with the typed word and can be undone', async ({
  app,
}) => {
  test.setTimeout(J.journey);
  await catalogIdle(app);
  await sweptOnce(app);
  const pathRule = (await app.api.get('/library/health')).rules.find(
    (r) => r.rule === 'path-mismatch',
  );
  expect(pathRule?.fixable, 'the managed library makes the path rule fixable').toBe(true);
  expect(pathRule?.failing ?? 0, 'the fixture files sit off the profile').toBeGreaterThan(0);
  const first = await app.api.post('/organize/preview', { data: {} });
  const picked = [...new Set(first.actions.map((a) => a.itemPid))].slice(0, 3);
  expect(picked.length, 'the dry run should move something').toBeGreaterThan(0);
  const pending = async () =>
    (await app.api.post('/organize/preview', { data: { itemPids: picked } })).totalActions;
  const before = await pending();
  // The runs already listed, so a run this test leaves standing is found
  // even when its answer never arrived.
  const listedBefore = new Set(
    (await app.api.get('/organize/history', { query: { limit: 100 } })).batches.map((b) => b.jobPid),
  );

  const page = app.page;
  const control = (id: string) => app.admin.control(id);
  await app.nav.enter('health');
  const isPreview = (r: Request) => r.url().endsWith('/organize/preview') && r.method() === 'POST';
  const previewed = page.waitForResponse((r) => isPreview(r.request()), { timeout: T.fetch });
  const previewMoves = control(SemanticsIds.healthFixPreview('path-mismatch'));
  await wheelIntoReach(page, previewMoves);
  await clickUntilRequested(page, previewMoves, isPreview);
  expect((await previewed).status()).toBe(200);
  await expect(control(SemanticsIds.organizePlan)).toBeVisible({ timeout: T.fetch });

  let applied = '';
  let undone = false;
  try {
    const isApply = (r: Request) => r.url().endsWith('/organize/apply') && r.method() === 'POST';
    applied = (
      await confirmTyped(app, control(SemanticsIds.organizeApply), 'ORGANIZE', SemanticsIds.organizeConfirm, isApply)
    ).jobPid;
    expect(applied).toMatch(/^jb-/);
    await expect(control(SemanticsIds.organizeReport)).toBeVisible({ timeout: T.fetch });
    expect(await pending(), 'the picked items should be in place').toBe(0);

    // The report's held files push the history screens below the fold,
    // where the list has not built its rows yet.
    const appliedRow = control(SemanticsIds.organizeHistoryRow(applied));
    await wheelIntoView(page, appliedRow);
    await expect(appliedRow).toBeVisible({ timeout: T.fetch });
    const isUndo = (r: Request) => r.url().endsWith('/organize/undo') && r.method() === 'POST';
    const undo = await confirmTyped(
      app,
      control(SemanticsIds.organizeUndo(applied)),
      'UNDO',
      SemanticsIds.organizeUndoConfirm,
      isUndo,
    );
    if (undo.held > 0) {
      // A held file stays where the run put it: the run is undone once
      // more, and a second hold fails here with the holds named.
      const again = await retryCatalogBusy(() =>
        app.api.post('/organize/undo', { data: { jobPid: applied } }),
      );
      expect(
        again.held,
        `the undo held ${JSON.stringify(undo.holds)}, and again ${JSON.stringify(again.holds)}`,
      ).toBe(0);
    }
    undone = true;
    await expect(control(SemanticsIds.organizeHistoryRow(undo.jobPid))).toBeVisible({ timeout: T.fetch });
    expect(await pending(), 'the picked items should be back where they were').toBe(before);
    expect(
      (await app.api.post('/organize/preview', { data: {} })).totalActions,
      'every file the run moved should be back where it was',
    ).toBe(first.totalActions);
  } finally {
    // Every later spec reads the fixture layout, so a run this test left
    // standing goes back however it ended, its answer captured or not,
    // once it is no longer running.
    if (!undone) {
      const history = async () =>
        (await app.api.get('/organize/history', { query: { limit: 100 } })).batches;
      const left =
        applied ||
        (await history()).find((b) => b.kind === 'organize' && !listedBefore.has(b.jobPid))?.jobPid;
      if (left) {
        await expect
          .poll(async () => (await app.api.get('/jobs/{pid}', { path: { pid: left } })).state, {
            timeout: T.fetch,
            message: 'the run left standing should end',
          })
          .not.toBe('running');
        if ((await history()).some((b) => b.jobPid === left && b.undoable)) {
          await retryCatalogBusy(() => app.api.post('/organize/undo', { data: { jobPid: left } }));
        }
      }
    }
  }
});
