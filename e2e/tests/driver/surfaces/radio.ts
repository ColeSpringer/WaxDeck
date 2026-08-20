// Radio: the hub, the dial, and the deck bar a live stream drives.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { clickInView } from '../gestures';

export class Radio extends Surface {
  /// One station's row in the library.
  station(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radio(pid)));
  }

  /// The band under the needle. Drawn only once three stations are
  /// pinned: below that the ticks sweep a width nothing occupies and the
  /// needle points through it, so the pins draw as rows instead.
  dial(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioDial));
  }

  /// One pinned station's row, which is what a dial too short to be one
  /// draws in its place.
  pinnedRow(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioPinned(pid)));
  }

  /// The dial's own control, which names what it will do.
  tune(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioTune));
  }

  /// The hub's own search control, which is its share of compact search:
  /// the shell owns no top app bar, so every rebuilt screen brings the
  /// control with it.
  searchAction(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.searchAction));
  }

  /// Pin a station, and hold to the star saying so.
  async pin(pid: string): Promise<void> {
    await this.setPinned(pid, true);
  }

  /// Unpin it, and hold to the star saying so.
  async unpin(pid: string): Promise<void> {
    await this.setPinned(pid, false);
  }

  /// Drive one star to a state, reading the state off the star itself.
  ///
  /// Not off the pinned surface, which is rebuilt whole on every change -
  /// rows below three pins, the band at three - so a gesture settling on
  /// one can catch it mid-rebuild, read the wrong thing and fire a second
  /// click that toggles the pin straight back. The star lives on the
  /// station's tile in the grid, which does not move, and its accessible
  /// name is the pin's own state.
  private async setPinned(pid: string, pinned: boolean): Promise<void> {
    const star = this.ctx.page.locator(sem(SemanticsIds.radioFavorite(pid)));
    const settled = pinned ? /^Unpin / : /^Pin /;
    // One computation for the guard and for the assertion. Read by hand
    // - aria-label with a textContent fallback - they disagree: a flutter
    // node often carries its name in a child span, so the raw text
    // arrives padded with newlines and an anchored regex misses it. The
    // helper then clicks again and unpins what it just pinned.
    const already = () =>
      expect(star)
        .toHaveAccessibleName(settled, { timeout: T.step })
        .then(() => true, () => false);
    await expect(async () => {
      if (!(await already())) {
        await star.click({ timeout: 2_000, force: true }).catch(() => {});
      }
      await expect(star).toHaveAccessibleName(settled, { timeout: T.step });
    }).toPass({ timeout: T.nav });
  }

  /// Tune a pinned station in from the surface that holds it, which
  /// takes the engine.
  ///
  /// clickInView: the pinned surface has only just appeared and is
  /// settling into place, so its control is a moving target for a single
  /// forced click. The deck bar is what proves the tune took.
  async tuneIn(target: Locator): Promise<void> {
    const bar = this.deckBar();
    await clickInView(this.ctx.page, target, { settled: bar });
    await bar.waitFor({ timeout: T.nav });
  }

  /// The deck bar a live stream drives.
  ///
  /// What a station is called lives in the bar's accessible name rather
  /// than in its text: the title block is excluded from semantics so the
  /// bar announces once instead of re-reading its own elapsed time at
  /// every tick.
  deckBar(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.deckBar));
  }

  /// The bar's star, which a station never has: per-user state does not
  /// exist for one, and a permanently greyed control reads as broken
  /// rather than as absent.
  deckStar(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.deckStar));
  }

  /// The hub's row into the songs kept off the air.
  savedDoor(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioSavedOpen));
  }

  /// The saved-songs screen itself.
  saved(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioSaved));
  }

  /// One kept song's row.
  savedEntry(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioSavedEntry(pid)));
  }

  /// The row's way into the library, which is what the list is for.
  savedFind(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioSavedFind(pid)));
  }

  /// Cross a row off. Forced: the row leaves optimistically, so what the
  /// removal did is the spec's assertion rather than anything here.
  async forgetSaved(pid: string): Promise<void> {
    await this.ctx.page
      .locator(sem(SemanticsIds.radioSavedRemove(pid)))
      .click({ force: true });
  }

  /// Stop the stream. Radio never enters the queue, so this puts the bar
  /// away entirely.
  async stop(): Promise<void> {
    await this.ctx.page.locator(sem(SemanticsIds.deckPlay)).click({ force: true });
  }

  /// The transport's own control, by the two true things it can say:
  /// stop (a paused live stream resumes at the live edge anyway, and the
  /// transport does not pretend otherwise), or tap-to-resume where the
  /// browser refused the programmatic start.
  transport(name: RegExp): Locator {
    return this.ctx.page.getByRole('button', { name }).first();
  }
}
