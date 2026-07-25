import { test, expect, APIRequestContext } from '@playwright/test';
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

  const card = page.locator(sem(SemanticsIds.item(book.pid)));
  await card.waitFor({ timeout: 30_000 });
  await clickThrough(card, page.locator(sem(SemanticsIds.bookResume)));

  await expect(page.locator(sem(SemanticsIds.chapter(0)))).toBeVisible();
  await expect(page.locator(sem(SemanticsIds.chapter(2)))).toBeVisible();
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
