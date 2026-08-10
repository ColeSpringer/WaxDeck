// The landing surface: shelves drawn off the discovery lists.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { wheelIntoView } from '../gestures';
import { DEST, Destination } from '../nav';

export class Home extends Surface {
  /// One shelf, by the collection list it draws from.
  shelf(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shelf(name)));
  }

  /// A shelf's way into the full enumeration behind it.
  shelfAll(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shelfAll(name)));
  }

  card(shelf: string, pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shelfCard(shelf, pid)));
  }

  /// Wheel a shelf below the fold into the semantics tree. Shelves are
  /// slivers, so one off screen is not built and has nothing to scroll
  /// to.
  async revealShelf(name: string): Promise<void> {
    await wheelIntoView(this.ctx.page, this.shelf(name));
  }

  /// Open the enumeration behind a shelf's Show all.
  ///
  /// Guarded rather than clicked through, and the guard is an incident
  /// rather than caution: the shelves above this one arrive on their own
  /// schedule and each one that resolves pushes the control down by its
  /// own height, so a click dispatched into that gap lands wherever the
  /// old rect now is. Under a full suite that is the episodes shelf's
  /// own Show all and a trip to Podcasts. So the click is answered by
  /// where it actually went rather than by waiting out an enumeration
  /// that was never coming.
  async showAll(shelf: string, dest: Destination): Promise<void> {
    const page = this.ctx.page;
    const control = this.shelfAll(shelf);
    const { path, arrival } = DEST[dest];
    const arrived = arrival(page);
    await expect(async () => {
      if (await arrived.isVisible()) return;
      if (new URL(page.url()).pathname !== path) {
        // Home first when a previous attempt left the app somewhere with
        // no handle on it: the control exists only here, and since the
        // path-URL flip getting back is a whole engine reboot rather
        // than a route change - so it is waited for rather than clicked
        // at on a step budget, which would spend every recovery proving
        // the app had not finished starting.
        if (!(await control.isVisible())) {
          await page.goto(DEST.home.path);
          await control.waitFor({ timeout: T.nav });
        }
        await control.click({ timeout: T.step, force: true });
        await expect
          .poll(() => new URL(page.url()).pathname, { timeout: T.step })
          .toBe(path);
      }
      await arrived.waitFor({ timeout: T.action });
    }).toPass({ timeout: T.fetch });
  }
}
