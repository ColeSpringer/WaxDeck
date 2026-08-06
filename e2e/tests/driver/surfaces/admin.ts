// The admin console: its section list, and the surfaces behind it.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';

export class Admin {
  constructor(private readonly ctx: Ctx) {}

  console(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.adminConsole));
  }

  /// One of the console's own sections, which is how Backups and the
  /// rest are reached now that the sidebar's Curation group holds a
  /// single entry for the whole console.
  section(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.adminSection(name)));
  }

  /// Import an archive through the backups screen's own control.
  ///
  /// The chooser event is armed before the click that opens it: a native
  /// dialog is not a page element, and there is no second chance to
  /// catch it once it is up.
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

  /// A control on an admin section that carries its own identifier.
  control(id: string): Locator {
    return this.ctx.page.locator(sem(id));
  }
}
