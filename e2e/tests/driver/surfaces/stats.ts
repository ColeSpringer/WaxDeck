// Listening stats, and the recap behind them.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { clickThrough, clickToward, wheelIntoReach, wheelIntoView } from '../gestures';

/// The media the page's switch scopes it to, as the wire names them.
export type StatsMedia = 'music' | 'podcast' | 'audiobook' | 'radio';

export class Stats extends Surface {
  range(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.statsRange(name)));
  }

  medium(name: StatsMedia): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.statsMedia(name)));
  }

  /// Scope the page to a medium, and hold the switch to what it does:
  /// something leaving the screen or something arriving on it. Retried
  /// as `narrowTo` is, the click plus its effect as one unit.
  async scopeTo(name: StatsMedia, goal: { gone: Locator } | { shows: Locator }): Promise<void> {
    await this.medium(name).waitFor({ timeout: T.assert });
    if ('gone' in goal) await expect(goal.gone).not.toHaveCount(0);
    await expect(async () => {
      await clickToward(this.medium(name), goal);
    }).toPass({ timeout: T.nav });
  }

  /// One ranked row of the top list, counted from the top.
  topEntry(nth: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.topEntry(nth)));
  }

  /// Open what a ranked row names, holding it to naming [name] first and
  /// settling on [settled]. Wheeled into reach: the list sits below the
  /// chart and the heatmap, culled until it is scrolled to.
  async openTopEntry(nth: number, name: string, settled: Locator): Promise<void> {
    const row = this.topEntry(nth);
    await wheelIntoReach(this.ctx.page, row);
    await expect(row).toContainText(name);
    await clickThrough(row, settled);
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
