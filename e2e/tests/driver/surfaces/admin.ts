// The admin console: its section list, and the surfaces behind it.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { typeInto, wheelIntoViewport } from '../gestures';

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
      await wheelIntoViewport(page, submit);
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
