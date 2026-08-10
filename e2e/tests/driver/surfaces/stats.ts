// Listening stats, and the recap behind them.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { clickThrough, clickToward, wheelIntoView } from '../gestures';

export class Stats extends Surface {
  range(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.statsRange(name)));
  }

  /// Switch the range, and hold the switch to something leaving the
  /// screen.
  ///
  /// Not `clickThrough`, which waits for something to appear: what a
  /// narrower range does is take figures away, and there is no new
  /// control to settle on. The click still has to retry - a canvas click
  /// can be swallowed while handlers attach - so the retried unit is the
  /// click plus the disappearance.
  async narrowTo(name: string, until: Locator): Promise<void> {
    // The chip has to be there before anything is decided. Without this
    // the whole method is a swallowed click plus "is `until` absent?",
    // so a renamed `stats-range-<name>` - or an `until` that was never
    // on screen - passes on the first attempt having switched nothing,
    // and the spec then asserts against the range it started in.
    await this.range(name).waitFor({ timeout: T.assert });
    await expect(until).not.toHaveCount(0);
    await expect(async () => {
      await clickToward(this.range(name), { gone: until });
    }).toPass({ timeout: T.nav });
  }

  /// The recap door, which sits at the bottom of the stats list. Wheeled
  /// into the semantics tree first, because the rows below the fold are
  /// culled and there is nothing to scroll to.
  async openYearInReview(): Promise<void> {
    const door = this.ctx.page.locator(sem(SemanticsIds.openYearInReview));
    await wheelIntoView(this.ctx.page, door, { by: 1_200 });
    await clickThrough(door, this.ctx.page.locator(sem(SemanticsIds.yirPersonal)));
  }

  /// Switch the recap to the server-wide view.
  async openServerRecap(settledOn: Locator): Promise<void> {
    await clickThrough(this.ctx.page.locator(sem(SemanticsIds.yirServer)), settledOn);
  }

  /// A figure the screen reports.
  ///
  /// The stat tiles merge into one semantics span whose raw text joins
  /// the segments with newlines, so a pattern that means "a space" has
  /// to say `\s+`. Recap content surfaces as merged text on some nodes
  /// and as a group's accessible name on others, so both renderings are
  /// accepted - which is why this is one method rather than a `text` and
  /// a `label`.
  figure(matcher: string | RegExp): Locator {
    return this.ctx.page.getByText(matcher).or(this.ctx.page.getByLabel(matcher));
  }
}
