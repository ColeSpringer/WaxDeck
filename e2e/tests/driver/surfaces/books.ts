// Audiobooks: the hub, a book, and the player's spoken face.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickThrough } from '../gestures';

export class Books {
  constructor(private readonly ctx: Ctx) {}

  hub(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.booksHub));
  }

  /// A book's card on the hub.
  card(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.book(pid)));
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

  /// Open a book from the hub.
  async open(pid: string): Promise<void> {
    await this.card(pid).waitFor({ timeout: T.nav });
    await clickThrough(this.card(pid), this.resume());
  }

  /// Resume, which starts playback.
  async play(): Promise<void> {
    await clickThrough(
      this.resume(),
      this.ctx.page.locator(sem(SemanticsIds.playerToggle)),
    );
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

  text(what: string | RegExp): Locator {
    return this.ctx.page.getByText(what).first();
  }
}
