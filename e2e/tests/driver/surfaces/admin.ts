// The admin console: its section list, and the surfaces behind it.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { DEST } from '../nav';
import { rectAtRest, typeInto, wheelIntoReach } from '../gestures';

export class Admin extends Surface {
  /// Import an archive through the backups screen's own control. The
  /// chooser event is armed before the click: a native dialog is not a
  /// page element, and there is no second chance once it is up.
  async importBackup(zipPath: string): Promise<void> {
    const page = this.ctx.page;
    const control = page.locator(sem(SemanticsIds.backupImport));
    // Armed and awaited together, so a click that throws cannot leave
    // the chooser promise rejecting later with nobody attached.
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      control.click({ force: true }),
    ]);
    await chooser.setFiles(zipPath);
  }


  /// Leave the first-run wizard: Skip, retried until the console is a
  /// console.
  ///
  /// Skip shares its card with the step's own doors, and the card
  /// rebuilds as the scan behind it advances - title, blurb and actions
  /// all change together - so the rect resolved for Skip is stale by
  /// the dispatch and the press lands on whatever door is drawn there
  /// now. One of those doors opens the review queue, which navigates -
  /// so a missed press is recovered through the console's own location,
  /// where the wizard, still unskipped, comes back with a Skip that can
  /// be pressed again. The at-rest read closes most of the rebuild
  /// window; the settled guard means a press that landed never fires
  /// twice.
  async skipWizard(): Promise<void> {
    const page = this.ctx.page;
    const skip = this.control(SemanticsIds.adminWizardSkip);
    const settled = this.control(SemanticsIds.adminTile('health'));
    await expect(async () => {
      if (await settled.isVisible()) return;
      if (!(await skip.isVisible())) {
        await page.goto(DEST.admin.path);
        await DEST.admin.arrival(page).waitFor({ timeout: T.nav });
        if (await settled.isVisible()) return;
        await skip.waitFor({ timeout: T.step });
      }
      await rectAtRest(skip);
      await skip.click({ timeout: 2_000, force: true }).catch(() => {});
      await settled.waitFor({ timeout: T.step });
    }).toPass({ timeout: T.fetch });
  }

  /// Fills the libraries screen's add form and submits it. The caller
  /// is already standing on that screen; creation starts a scan of its
  /// own, which is the server's behaviour rather than this method's.
  ///
  /// Retried against the POST, because nothing on the DOM side proves
  /// the app took the form and the table above can move the button out
  /// from under the press.
  ///
  /// A retry cannot double-create, because the server refuses a
  /// duplicate name - so an attempt whose answer arrived too late to be
  /// read meets its own library on the next one, and a 409 counts as
  /// created rather than wedging the loop until the budget runs out.
  ///
  /// Armed and awaited together, the way `importBackup` does it: a click
  /// on a canvas node can throw, and an orphaned wait would then reject
  /// later with nobody attached.
  async addLibrary(who: { name: string; path: string }): Promise<void> {
    const page = this.ctx.page;
    const submit = page.locator(sem(SemanticsIds.librarySubmit));
    await expect(async () => {
      await typeInto(page, page.locator(sem(SemanticsIds.libraryName)), who.name);
      await typeInto(page, page.locator(sem(SemanticsIds.libraryPath)), who.path);
      await wheelIntoReach(page, submit);
      const [answered] = await Promise.all([
        page.waitForResponse(
          (r) => r.url().includes('/libraries') && r.request().method() === 'POST',
          { timeout: T.step },
        ),
        submit.click({ timeout: T.step }),
      ]);
      expect(answered.ok() || answered.status() === 409).toBe(true);
    }).toPass({ timeout: T.fetch });
  }
}
