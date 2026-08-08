import { test, expect } from './fixtures';
import { J, T } from './driver';

// The audiobook journey: the scanned multi-part fixture book presents
// one timeline, a position written by another device resolves to the
// right chapter, and the web client resumes there.
//
// Parallel now. These three all write the fixture book's own play
// position - one to hand a place over between devices, one to mark it
// finished, one to start from the top - and that used to make them a
// serial group, because four workers shared one account and so one row.
// A play position is per listener: each of these owns its own.

test('a multi-part book resumes at the right chapter across devices', async ({ app }) => {
  test.setTimeout(J.long);
  const book = await app.seed.book('The Fixture Book');

  // The book is one item over three parts with a book-spanning
  // timeline; chapters cover it end to end.
  const detail = await app.api.get('/books/{pid}', { path: { pid: book.pid } });
  expect(detail.parts.length).toBe(3);
  expect(detail.chapters.length).toBeGreaterThanOrEqual(3);
  expect(detail.parts[2].startMs).toBeGreaterThan(0);

  // Another device leaves off inside the second part.
  const target = detail.parts[1].startMs + Math.floor(detail.parts[1].durationMs / 2);
  await app.seed.setPosition(book.pid, target);

  // The resume endpoint answers with the chapter that position is in.
  const resume = await app.api.get('/books/{pid}/resume', { path: { pid: book.pid } });
  expect(resume.positionMs).toBe(target);
  expect(resume.chapter, 'the resume point carries its chapter').toBeTruthy();
  expect(resume.chapter!.startMs).toBeLessThanOrEqual(target);

  // Play-info resolves the part containing that position.
  const info = await app.api.get('/items/{pid}/play-info', {
    path: { pid: book.pid },
    query: { positionMs: target },
  });
  expect(info.partIndex).toBe(1);
  expect(info.partCount).toBe(3);
  expect(info.partStartMs).toBe(detail.parts[1].startMs);

  // This device: the book screen shows chapters and resumes there. Books
  // are their own destination - the library grid no longer holds them.
  await app.nav.enter('books');
  await app.books.open(book.pid);

  await expect(app.books.chapter(0)).toBeVisible();
  await expect(app.books.chapter(2)).toBeVisible();
  // A multi-file book says so where a listener is looking at it.
  await expect(app.books.partsNote()).toBeVisible();
  await app.books.play();

  // Playback continues on the book timeline: the next checkpoints land
  // at or past the cross-device position, never back at zero.
  await expect
    .poll(
      async () =>
        (await app.api.tryGet('/items/{pid}/play-state', { path: { pid: book.pid } }))
          ?.positionMs ?? 0,
      { timeout: T.fetch, message: 'resumed playback should checkpoint past the handoff' },
    )
    .toBeGreaterThanOrEqual(target);
});

test('the hub sorts, filters, and marks a book finished', async ({ app }) => {
  test.setTimeout(J.long);
  const book = await app.seed.book('The Fixture Book');

  // Start from nothing heard, so the position half is about a known
  // state.
  await app.seed.setPosition(book.pid, 0);

  await app.nav.enter('books');
  const card = app.books.card(book.pid);
  await card.waitFor({ timeout: T.nav });

  // Sort is a standing choice in the overflow, and the shelf redraws
  // under it rather than reloading.
  await app.books.sortBy('title');
  await expect(card).toBeVisible();

  // Marking it finished is a position write at the book's own end,
  // which is what the server derives "finished" from.
  await app.books.open(book.pid);
  await app.books.markFinished();

  await expect
    .poll(
      async () =>
        (await app.api.tryGet('/items/{pid}/play-state', { path: { pid: book.pid } }))
          ?.finished ?? false,
      { timeout: T.fetch, message: 'mark finished should be a position write at the end' },
    )
    .toBeTruthy();

  // And the undo puts back where the listener was, which was the top.
  await app.shell.snackAction('Undo').click();
  await expect
    .poll(
      async () =>
        (await app.api.tryGet('/items/{pid}/play-state', { path: { pid: book.pid } }))
          ?.positionMs ?? -1,
      { timeout: T.fetch, message: 'undo should restore the position it replaced' },
    )
    .toBe(0);

  // The filters, against state this test establishes on purpose rather
  // than inherits. The undo above really does undo: it puts the flags
  // back beside the position, so the book is unfinished again by the
  // time the filters run. (This block used to lean on the opposite -
  // that marking finished could not be taken back - which stopped being
  // true when that bug was fixed, and left the spec asserting a state
  // nothing produced any more.)
  //
  // So both books are finished through the seeder. The empty state
  // below is the reason it has to be both: it appears only when a
  // filter matches nothing at all, which is a claim about every book in
  // the library rather than about this one. Per-account state, wholly
  // this test's.
  const other = await app.seed.book('The Chaptered Fixture');
  await app.seed.setPosition(other.pid, other.durationMs);
  await app.seed.setPosition(book.pid, book.durationMs);
  // Polled rather than assumed: "finished" is derived from the position
  // a write lands at, so this is the one place the filter's input is
  // worth confirming before the filter is judged on it.
  await expect
    .poll(
      async () =>
        (await app.api.tryGet('/items/{pid}/play-state', { path: { pid: book.pid } }))
          ?.finished ?? false,
      { timeout: T.fetch, message: 'a position at the end should read as finished' },
    )
    .toBeTruthy();

  // Finished holds it; unfinished does not, and says so rather than
  // leaving an empty grid with no way out.
  await app.nav.enter('books');
  await app.books.filterFinished('finished');
  await expect(card).toBeVisible();
  await app.books.filterFinished('unfinished');
  await expect(app.books.text('Nothing matches')).toBeVisible();
  await expect(card).toBeHidden();
  await app.books.action('Show all books').click();
  await expect(card).toBeVisible();
});

test('the book player spans a chapter, and bookmarks keep a place', async ({ app }) => {
  test.setTimeout(J.long);
  const book = await app.seed.book('The Fixture Book');

  // From the top, so the chapter the bar spans is a known one, and with
  // no marks left over from a run this test has already made.
  await app.seed.setPosition(book.pid, 0);
  await app.seed.clearBookmarks(book.pid);

  await app.nav.enter('books');
  await app.books.open(book.pid);
  await app.books.play();

  // The chapter is the unit the bar spans, and the whole book is one
  // press away: a nine-hour bar moves a pixel a minute, and "how far
  // through the book am I" is the question the chapter view cannot
  // answer on its own.
  await expect(app.player.timeline('chapter')).toBeVisible({ timeout: T.nav });
  await app.player.spanWholeBook();
  await expect(app.player.text(/percent/)).toBeVisible();

  // The chapter list is the player's own bottom region, not a button
  // that opens a sheet.
  await expect(app.player.chapter(0)).toBeVisible();

  // A bookmark keeps a place on purpose, which is a different thing
  // from the resume position the transport writes on its own.
  await app.player.addBookmark('the riddle');
  await expect(app.player.bookmark(0)).toBeVisible();

  const stored = await app.api.get('/books/{pid}/bookmarks', { path: { pid: book.pid } });
  expect(
    stored.bookmarks,
    'the mark should belong to the account, on the server',
  ).toHaveLength(1);
  expect(stored.bookmarks![0].note).toBe('the riddle');

  // And removing it is the listener's, not a side effect of listening
  // past it.
  await app.player.deleteBookmark(0);
  await expect
    .poll(
      async () =>
        (await app.api.tryGet('/books/{pid}/bookmarks', { path: { pid: book.pid } }))
          ?.bookmarks?.length ?? -1,
      { timeout: T.fetch, message: 'deleting a bookmark should remove it server-side' },
    )
    .toBe(0);
});
