// The landing surface: shelves drawn off the discovery lists.

import { expect, Locator } from '@playwright/test';
import {
  SemanticsIdPrefixes,
  SemanticsIds,
  sem,
  semPrefix,
} from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import {
  clickToward,
  MENU_UNIT,
  rectAtRest,
  wheelIntoReach,
  wheelIntoView,
} from '../gestures';
import { DEST, Destination } from '../nav';

/// The shelves drawn by ItemShelf, whose cards raise the shared item
/// menu. The other shelves' cards do not - downloaded and episodes carry
/// their own affordances, and a pinned card raises the unpin sheet - so
/// the type keeps a spec from asking a card for a menu it never had,
/// which would otherwise fail late as a missing sheet.
export type ItemShelfName =
  | 'continue'
  | 'recent'
  | 'sealed'
  | 'rediscover'
  | 'most-played';

export class Home extends Surface {
  /// One shelf, by the collection list it draws from.
  shelf(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shelf(name)));
  }

  /// A shelf's way into the full enumeration behind it.
  shelfAll(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shelfAll(name)));
  }

  /// The paging chevrons, each armed only while there is somewhere to
  /// go that way.
  shelfBack(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shelfBack(name)));
  }

  shelfForward(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shelfForward(name)));
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

  /// Raise a card's overflow menu the way a pointer does, and leave it
  /// standing for the caller to read. Proof of arrival is the sheet's
  /// own pid handle, so a menu raised on the wrong card can never
  /// satisfy the gesture.
  ///
  /// The wheel is the load-bearing half, and a secondary tap is the
  /// gesture. [revealShelf] proves a shelf is built, not that it is
  /// where a click reaches it, and a card scrolled half under the app
  /// bar still publishes a box - a clipped one, whose centre is no
  /// longer over the card. A right click aimed there raised the first
  /// Never played card's menu instead, two shelves down. The wheel sits
  /// inside the retried unit, so a card the arriving shelves above have
  /// pushed since the last attempt is re-reached rather than clicked
  /// where it was.
  async openCardMenu(shelf: ItemShelfName, pid: string): Promise<void> {
    const card = this.card(shelf, pid);
    const sheet = this.control(SemanticsIds.itemMenuSheet(pid));
    await expect(async () => {
      if (await sheet.isVisible()) return;
      await this.dismissStraySheet();
      await wheelIntoReach(this.ctx.page, card);
      await clickToward(card, { shows: sheet }, { button: 'right' });
    }).toPass({ timeout: T.nav });
  }

  /// Sends away an item sheet that is not the one being asked for. A
  /// misaimed press raises some other card's sheet, and its modal
  /// barrier drops every node behind it from the semantics tree - so a
  /// retry that went straight back to the card would wait on a node
  /// that cannot exist until the wrong sheet is gone.
  private async dismissStraySheet(): Promise<void> {
    const any = this.ctx.page.locator(
      semPrefix(SemanticsIdPrefixes.itemMenuSheet),
    );
    if (!(await any.first().isVisible())) return;
    await this.ctx.page.keyboard.press('Escape');
    await expect(any).toHaveCount(0, { timeout: T.step });
  }

  /// The same menu, and a row picked from it, as one retried unit -
  /// [chooseFromMenu]'s shape around this surface's own opener.
  /// `settled` is what only that row can produce - the screen it opens.
  async chooseFromCardMenu(
    shelf: ItemShelfName,
    pid: string,
    item: Locator,
    settled?: Locator,
  ): Promise<void> {
    const card = this.card(shelf, pid);
    const sheet = this.control(SemanticsIds.itemMenuSheet(pid));
    await expect(async () => {
      if (settled && (await settled.isVisible())) return;
      if (!(await sheet.isVisible())) {
        await this.dismissStraySheet();
        await wheelIntoReach(this.ctx.page, card);
        await clickToward(card, { shows: sheet }, { button: 'right' });
      }
      await rectAtRest(item);
      await item.click({ force: true });
      if (settled) {
        await settled.waitFor({ timeout: T.step });
      } else {
        await expect(item).toBeHidden({ timeout: T.step });
      }
    }).toPass({ timeout: MENU_UNIT });
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
