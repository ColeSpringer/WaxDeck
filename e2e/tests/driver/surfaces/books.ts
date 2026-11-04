// Audiobooks: the hub, a book, and the player's spoken face.

import { Locator, Request, expect } from '@playwright/test';
import { SemanticsIdPrefixes, SemanticsIds, sem, semPrefix } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { DEST } from '../nav';
import {
  chooseFromMenu,
  clickThrough,
  clickToward,
  clickUntilRequested,
  rectAtRest,
  requestSeen,
  wheelIntoReach,
} from '../gestures';

/// The indexes the hub's tiles open.
export type BookIndex = 'authors' | 'genres';

export class Books extends Surface {
  /// A book's card on the hub.
  card(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.book(pid)));
  }

  /// A book's card on the hub's Continue listening shelf.
  continueCard(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookContinue(pid)));
  }

  /// The resume control on a book's own screen, which the hub does not
  /// draw - so it is what tells the two apart.
  resume(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookResume));
  }

  /// The note a multi-file book carries where a listener is looking at
  /// it.
  partsNote(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookPartsNote));
  }

  chapter(index: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.chapter(index)));
  }

  /// Open a book from the hub. The grid builds only the cards near the
  /// view, and the continue row landing above it can push a card out of
  /// reach after it was found, so each try wheels the hub toward it.
  async open(pid: string): Promise<void> {
    const page = this.ctx.page;
    const hub = page.locator(sem(SemanticsIds.booksHub));
    const card = this.card(pid);
    await hub.waitFor({ timeout: T.nav });
    await expect(async () => {
      // A press that landed with the book merely slow to open leaves the
      // card gone, and a try that went looking for it would never see the
      // book.
      if (await this.resume().isVisible()) return;
      if (!(await card.isVisible())) {
        const box = await hub.boundingBox();
        expect(box, 'the hub reports a box to wheel over').toBeTruthy();
        await page.mouse.move(box!.x + box!.width / 2, (page.viewportSize()?.height ?? 720) / 2);
        await page.mouse.wheel(0, 400);
        await expect(card).toBeVisible({ timeout: 1_000 });
      }
      await wheelIntoReach(page, card, { appear: 1_000 });
      await clickToward(card, { shows: this.resume() }, { aim: 'caption' });
    }).toPass({ timeout: T.nav });
  }

  /// Resume, which starts playback in the dock. Settles on the deck
  /// bar, so with something already playing the click is skipped.
  async play(): Promise<void> {
    await clickThrough(
      this.resume(),
      this.ctx.page.locator(sem(SemanticsIds.deckBar)),
    );
  }

  /// Play a book from its cover on the hub, where it stands. The play is
  /// its own node, drawn only while a pointer rests on the card, so each
  /// try hovers the card and clicks the play at its own rect. Settles on
  /// the start's play-info request: the deck bar may already be up with
  /// a queue the account left behind.
  async playCover(pid: string): Promise<void> {
    const page = this.ctx.page;
    const card = this.card(pid);
    const play = page.locator(sem(SemanticsIds.bookPlay(pid)));
    const started = requestSeen(page, startOf(pid));
    await wheelIntoReach(page, card);
    await expect(async () => {
      if (started()) return;
      const box = await card.boundingBox();
      expect(box, 'the card reports a box to hover').toBeTruthy();
      // The top of the card is its cover.
      await page.mouse.move(box!.x + box!.width / 2, box!.y + box!.width / 2);
      await play.waitFor({ timeout: T.step });
      await rectAtRest(play);
      await play.click({ timeout: 2_000, force: true }).catch(() => {});
      await expect
        .poll(started, { timeout: T.step, message: 'the cover should start the book' })
        .toBe(true);
    }).toPass({ timeout: T.nav });
  }

  /// Carry a book on from the hub's Continue listening card, whose tap
  /// resumes rather than opening the book. Pressed on the caption, off
  /// the cover, whose hover play is the other way to resume. Settles as
  /// [playCover] does.
  async continueResume(pid: string): Promise<void> {
    const page = this.ctx.page;
    const card = this.continueCard(pid);
    await wheelIntoReach(page, card);
    await clickUntilRequested(page, card, startOf(pid), { aim: 'caption' });
  }

  /// Sort is a standing choice in the hub's overflow.
  ///
  /// `chooseFromMenu`, not `clickThrough` plus a bare click. That
  /// gesture re-clicks its trigger while it waits, which for a menu
  /// lands on the modal barrier and closes the one it just opened; and
  /// the bare click that followed skipped the rect-at-rest check whose
  /// absence is recorded in gestures.ts as choosing the row beneath the
  /// one aimed at.
  async sortBy(name: string): Promise<void> {
    const page = this.ctx.page;
    await chooseFromMenu(
      page.locator(sem(SemanticsIds.booksHubOverflow)),
      page.locator(sem(SemanticsIds.bookSort(name))),
    );
  }

  /// Narrow the hub to finished or unfinished books.
  ///
  /// Forced, like every chip over canvas: a semantics node laid over a
  /// shelf that is still settling never satisfies Playwright's own
  /// stability heuristics, so an actionability wait here is a timeout
  /// rather than a safety net. What the chip did is the spec's
  /// assertion, and it differs per chip - one brings the card back, the
  /// other takes it away - so there is nothing for this to settle on.
  async filterFinished(name: 'finished' | 'unfinished'): Promise<void> {
    await this.ctx.page
      .locator(sem(SemanticsIds.bookFinishedFilter(name)))
      .click({ force: true });
  }

  /// Mark a book finished, which the server derives from a position
  /// write at the book's own end.
  ///
  /// The one in this file where the gesture matters most: marking
  /// finished cannot be undone (docs/bugs.md - the snack's Undo gives
  /// the position back and leaves the flag set), so a click that lands
  /// one row off does something permanent to the account and nothing
  /// says so. `chooseFromMenu` is what holds the row still first.
  async markFinished(): Promise<void> {
    const page = this.ctx.page;
    await chooseFromMenu(
      page.locator(sem(SemanticsIds.bookOverflow)),
      page.locator(sem(SemanticsIds.bookMarkFinished)),
    );
  }

  /// A control the hub or a book draws by its label - the filters' own
  /// way out, an empty state's offer. Copy, so the spec names it.
  action(name: string): Locator {
    return this.ctx.page.getByRole('button', { name });
  }

  /// The link on a book screen into the series it belongs to.
  seriesLink(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookSeriesLink));
  }

  /// One series' own screen.
  series(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookSeriesScreen(pid)));
  }

  /// One book's row on a series screen, by its place in the list.
  seriesRow(index: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookSeriesRow(index)));
  }

  /// The full series index, and the hub shelf's way into it.
  seriesIndex(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookSeriesIndex));
  }

  seriesShowAll(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookSeriesSeeAll));
  }

  /// Follow a book's series line, settling on the series screen. A
  /// retried unit, as every other navigation here is: a part-scrolled
  /// Flutter node publishes a clipped rect whose centre can miss the
  /// widget, and a single forced click has nothing to try again.
  async openSeries(pid: string): Promise<void> {
    await clickThrough(this.seriesLink(), this.series(pid));
  }

  /// Open one book from the series screen, settling on the book.
  async openFromSeries(index: number): Promise<void> {
    await clickThrough(this.seriesRow(index), this.resume());
  }

  /// Follow the hub shelf's Show all into the index.
  async openSeriesIndex(): Promise<void> {
    await clickThrough(this.seriesShowAll(), this.seriesIndex());
  }

  seriesCard(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookSeriesCard(pid)));
  }

  /// A tile on the hub: the way into one index.
  tile(name: BookIndex | 'series'): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookTile(name)));
  }

  /// Open an index from the hub's tile, settling on its first row.
  async openIndex(name: BookIndex): Promise<void> {
    await clickThrough(
      this.tile(name),
      this.ctx.page.locator(sem(SemanticsIds.indexBucket(0))),
    );
  }

  /// An index row by the name it shows. Rows are numbered by position,
  /// which other workers' books shift, so a spec names the one it means.
  /// Anchored at the row's start, so a name another one merely contains
  /// is not a second match.
  indexRow(label: string): Locator {
    const rows = `${semPrefix(SemanticsIdPrefixes.indexBucket)}:not(${semPrefix(SemanticsIdPrefixes.indexBucketMore)})`;
    const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return this.ctx.page.locator(rows).filter({ hasText: new RegExp(`^${escaped}`) });
  }

  /// One author's page, by the author's artist pid.
  authorPage(key: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.bookAuthorScreen(key)));
  }

  /// Where a book's page lives, for a spec that checks it stayed.
  bookLocation(pid: string): string {
    return `${DEST.books.path}/${encodeURIComponent(pid)}`;
  }

  /// Where an author's page lives, for a spec that checks it arrived.
  authorLocation(key: string): string {
    return `${DEST.books.path}/authors/${encodeURIComponent(key)}`;
  }

  /// Open an author from the Authors index, settling on their page. The
  /// index is built lazily and lists every worker's authors, so the row
  /// is wheeled into reach first; two rows of one name fail here, by
  /// name, rather than as a click that never lands.
  async openAuthor(label: string, key: string): Promise<void> {
    const row = this.indexRow(label);
    await wheelIntoReach(this.ctx.page, row);
    await expect(row, `one Authors row reads ${label}`).toHaveCount(1);
    await clickThrough(row, this.authorPage(key));
  }
}

/// [pid]'s play-info request, the first thing a start of it asks.
function startOf(pid: string): (req: Request) => boolean {
  return (req) => req.url().includes(`/items/${pid}/play-info`);
}
