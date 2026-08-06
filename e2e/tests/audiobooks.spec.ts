import { legacyTest as test, expect, APIRequestContext } from './fixtures';
import {
  ADMIN_PASS,
  ADMIN_USER,
  authed,
  clickThrough,
  ensureAdmin,
  typeInto,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The audiobook journey: the scanned multi-part fixture book presents
// one timeline, a position written by another device resolves to the
// right chapter, and the web client resumes there.
//
// Serial, not parallel. Both tests write the fixture book's own play
// position - one to hand a place over between devices, one to mark it
// finished - and the suite runs four workers against one server and one
// account, so the two would otherwise race over the same row.


async function fixtureBook(request: APIRequestContext, token: string): Promise<{ pid: string; durationMs: number }> {
  let pid = '';
  let durationMs = 0;
  await expect
    .poll(
      async () => {
        const resp = await request.get('/api/v1/library/items?mediaType=audiobook', authed(token));
        if (!resp.ok()) return false;
        const items = ((await resp.json()).items ?? []) as any[];
        const hit = items.find((it) => it.title === 'The Fixture Book');
        if (!hit) return false;
        pid = hit.pid;
        durationMs = hit.durationMs;
        return true;
      },
      { timeout: 60_000, message: 'the startup scan should index the fixture book' },
    )
    .toBeTruthy();
  return { pid, durationMs };
}

test.describe.serial('audiobooks', () => {
  test('a multi-part book resumes at the right chapter across devices', async ({ page, request }) => {
    test.setTimeout(180_000);
    const token = await ensureAdmin(request);
    const book = await fixtureBook(request, token);

    // The book is one item over three parts with a book-spanning
    // timeline; chapters cover it end to end.
    const detailResp = await request.get(`/api/v1/books/${book.pid}`, authed(token));
    expect(detailResp.ok()).toBeTruthy();
    const detail = await detailResp.json();
    expect(detail.parts.length).toBe(3);
    expect(detail.chapters.length).toBeGreaterThanOrEqual(3);
    expect(detail.parts[2].startMs).toBeGreaterThan(0);

    // Another device leaves off inside the second part.
    const target = detail.parts[1].startMs + Math.floor(detail.parts[1].durationMs / 2);
    const checkpoint = await request.put(`/api/v1/items/${book.pid}/play-state`, {
      ...authed(token),
      data: { positionMs: target },
    });
    expect(checkpoint.ok()).toBeTruthy();

    // The resume endpoint answers with the chapter that position is in.
    const resumeResp = await request.get(`/api/v1/books/${book.pid}/resume`, authed(token));
    expect(resumeResp.ok()).toBeTruthy();
    const resume = await resumeResp.json();
    expect(resume.positionMs).toBe(target);
    expect(resume.chapter, 'the resume point carries its chapter').toBeTruthy();
    expect(resume.chapter.startMs).toBeLessThanOrEqual(target);

    // Play-info resolves the part containing that position.
    const infoResp = await request.get(
      `/api/v1/items/${book.pid}/play-info?positionMs=${target}`,
      authed(token),
    );
    expect(infoResp.ok()).toBeTruthy();
    const info = await infoResp.json();
    expect(info.partIndex).toBe(1);
    expect(info.partCount).toBe(3);
    expect(info.partStartMs).toBe(detail.parts[1].startMs);

    // This device: the book screen shows chapters and resumes there.
    await page.goto('/');
    const username = page.getByRole('textbox', { name: 'Username' });
    await username.waitFor({ timeout: 30_000 });
    await typeInto(page, username, ADMIN_USER);
    await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
    await page.getByRole('button', { name: 'Log in' }).click();

    // Books are their own destination now: the hub, then the book. The
    // library grid no longer holds them.
    await clickThrough(
      page.locator(sem(SemanticsIds.navDestination('books'))),
      page.locator(sem(SemanticsIds.booksHub)),
    );
    const card = page.locator(sem(SemanticsIds.book(book.pid)));
    await card.waitFor({ timeout: 30_000 });
    await clickThrough(card, page.locator(sem(SemanticsIds.bookResume)));

    await expect(page.locator(sem(SemanticsIds.chapter(0)))).toBeVisible();
    await expect(page.locator(sem(SemanticsIds.chapter(2)))).toBeVisible();
    // A multi-file book says so where a listener is looking at it.
    await expect(page.locator(sem(SemanticsIds.bookPartsNote))).toBeVisible();
    await clickThrough(
      page.locator(sem(SemanticsIds.bookResume)),
      page.locator(sem(SemanticsIds.playerToggle)),
    );

    // Playback continues on the book timeline: the next checkpoints land
    // at or past the cross-device position, never back at zero.
    await expect
      .poll(
        async () => {
          const resp = await request.get(`/api/v1/items/${book.pid}/play-state`, authed(token));
          if (!resp.ok()) return 0;
          return (await resp.json()).positionMs as number;
        },
        { timeout: 30_000, message: 'resumed playback should checkpoint past the handoff point' },
      )
      .toBeGreaterThanOrEqual(target);
  });

  test('the hub sorts, filters, and marks a book finished', async ({ page, request }) => {
    test.setTimeout(180_000);
    const token = await ensureAdmin(request);
    const book = await fixtureBook(request, token);

    // Start from nothing heard, so the filters are about a known state.
    await request.put(`/api/v1/items/${book.pid}/play-state`, {
      ...authed(token),
      data: { positionMs: 0 },
    });

    await page.goto('/');
    const username = page.getByRole('textbox', { name: 'Username' });
    await username.waitFor({ timeout: 30_000 });
    await typeInto(page, username, ADMIN_USER);
    await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
    await page.getByRole('button', { name: 'Log in' }).click();

    await clickThrough(
      page.locator(sem(SemanticsIds.navDestination('books'))),
      page.locator(sem(SemanticsIds.booksHub)),
    );
    const card = page.locator(sem(SemanticsIds.book(book.pid)));
    await card.waitFor({ timeout: 30_000 });

    // Sort is a standing choice in the overflow, and the shelf redraws
    // under it rather than reloading.
    await clickThrough(
      page.locator(sem(SemanticsIds.booksHubOverflow)),
      page.locator(sem(SemanticsIds.bookSort('title'))),
    );
    await page.locator(sem(SemanticsIds.bookSort('title'))).click({ force: true });
    await expect(card).toBeVisible();

    // Unfinished holds it; finished does not, and says so rather than
    // leaving an empty grid with no way out.
    await page
      .locator(sem(SemanticsIds.bookFinishedFilter('unfinished')))
      .click({ force: true });
    await expect(card).toBeVisible();
    await page
      .locator(sem(SemanticsIds.bookFinishedFilter('finished')))
      .click({ force: true });
    await expect(page.getByText('Nothing matches')).toBeVisible();
    await expect(card).toBeHidden();
    await page.getByRole('button', { name: 'Show all books' }).click();
    await expect(card).toBeVisible();

    // Marking it finished is a position write at the book's own end,
    // which is what the server derives "finished" from.
    await clickThrough(card, page.locator(sem(SemanticsIds.bookResume)));
    await clickThrough(
      page.locator(sem(SemanticsIds.bookOverflow)),
      page.locator(sem(SemanticsIds.bookMarkFinished)),
    );
    await page.locator(sem(SemanticsIds.bookMarkFinished)).click({ force: true });

    await expect
      .poll(
        async () => {
          const resp = await request.get(`/api/v1/items/${book.pid}/play-state`, authed(token));
          if (!resp.ok()) return false;
          return (await resp.json()).finished as boolean;
        },
        { timeout: 30_000, message: 'mark finished should be a position write at the end' },
      )
      .toBeTruthy();

    // And the undo puts back where the listener was, which was the top.
    await page.getByRole('button', { name: 'Undo' }).click();
    await expect
      .poll(
        async () => {
          const resp = await request.get(`/api/v1/items/${book.pid}/play-state`, authed(token));
          if (!resp.ok()) return -1;
          return (await resp.json()).positionMs as number;
        },
        { timeout: 30_000, message: 'undo should restore the position it replaced' },
      )
      .toBe(0);
  });

  test('the book player spans a chapter, and bookmarks keep a place', async ({
    page,
    request,
  }) => {
    test.setTimeout(180_000);
    const token = await ensureAdmin(request);
    const book = await fixtureBook(request, token);

    // From the top, so the chapter the bar spans is a known one.
    await request.put(`/api/v1/items/${book.pid}/play-state`, {
      ...authed(token),
      data: { positionMs: 0 },
    });
    // And with no marks left over from a previous run: the account is
    // shared by the whole suite, so this test owns what it makes and
    // nothing else.
    const existing = await request.get(`/api/v1/books/${book.pid}/bookmarks`, authed(token));
    for (const mark of ((await existing.json()).bookmarks ?? []) as Array<{ id: string }>) {
      await request.delete(`/api/v1/books/${book.pid}/bookmarks/${mark.id}`, authed(token));
    }

    await page.goto('/');
    const username = page.getByRole('textbox', { name: 'Username' });
    await username.waitFor({ timeout: 30_000 });
    await typeInto(page, username, ADMIN_USER);
    await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
    await page.getByRole('button', { name: 'Log in' }).click();

    await clickThrough(
      page.locator(sem(SemanticsIds.navDestination('books'))),
      page.locator(sem(SemanticsIds.booksHub)),
    );
    const card = page.locator(sem(SemanticsIds.book(book.pid)));
    await card.waitFor({ timeout: 30_000 });
    await clickThrough(card, page.locator(sem(SemanticsIds.bookResume)));
    await clickThrough(
      page.locator(sem(SemanticsIds.bookResume)),
      page.locator(sem(SemanticsIds.playerToggle)),
    );

    // The chapter is the unit the bar spans, and the whole book is one
    // press away: a nine-hour bar moves a pixel a minute, and "how far
    // through the book am I" is the question the chapter view cannot
    // answer on its own.
    await expect(page.locator(sem(SemanticsIds.playerTimeline('chapter')))).toBeVisible({
      timeout: 30_000,
    });
    await page.locator(sem(SemanticsIds.playerTimeline('book'))).click({ force: true });
    await expect(page.getByText(/percent/).first()).toBeVisible();

    // The chapter list is the player's own bottom region since P19, not
    // a button that opens a sheet.
    await expect(page.locator(sem(SemanticsIds.playerChapter(0)))).toBeVisible();

    // A bookmark keeps a place on purpose, which is a different thing
    // from the resume position the transport writes on its own.
    await clickThrough(
      page.locator(sem(SemanticsIds.playerBookmarks)),
      page.locator(sem(SemanticsIds.playerBookmarkSheet)),
    );
    await typeInto(page, page.locator(sem(SemanticsIds.playerBookmarkNote)), 'the riddle');
    await page.locator(sem(SemanticsIds.playerBookmarkAdd)).click({ force: true });

    await expect(page.locator(sem(SemanticsIds.playerBookmark(0)))).toBeVisible({
      timeout: 15_000,
    });
    const marks = await request.get(`/api/v1/books/${book.pid}/bookmarks`, authed(token));
    const stored = ((await marks.json()).bookmarks ?? []) as Array<{
      id: string;
      note?: string;
    }>;
    expect(stored, 'the mark should belong to the account, on the server').toHaveLength(1);
    expect(stored[0].note).toBe('the riddle');

    // And removing it is the listener's, not a side effect of listening
    // past it.
    await page.locator(sem(SemanticsIds.playerBookmarkDelete(0))).click({ force: true });
    await expect
      .poll(
        async () => {
          const resp = await request.get(`/api/v1/books/${book.pid}/bookmarks`, authed(token));
          if (!resp.ok()) return -1;
          return ((await resp.json()).bookmarks ?? []).length as number;
        },
        { timeout: 30_000, message: 'deleting a bookmark should remove it server-side' },
      )
      .toBe(0);
  });
});
