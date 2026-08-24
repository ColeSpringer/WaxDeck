// The metadata editor, and the item-menu door listing rows open into
// it. The editor itself is one screen wherever it was opened from; the
// doors are per-surface (a row's kebab, a card's right click), so the
// spec opens the menu with the surface's own gesture and this surface
// takes it from the sheet to the editor.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';

export class Metadata extends Surface {
  /// The editor screen, whichever surface opened it.
  editor(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.metadataEditor));
  }

  /// The refusal page the editor answers a non-curator with.
  forbidden(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.metadataForbidden));
  }

  /// The edit entry for one item on whichever row menu is open.
  editEntry(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.editMetadata(pid)));
  }

  /// From an open row menu into the editor: click the sheet's edit
  /// entry and wait for the editor screen (or the refusal, which is a
  /// real arrival too - the caller asserts which).
  async openEditorFromRow(pid: string): Promise<void> {
    await this.editEntry(pid).click({ timeout: T.step });
    await this.editor()
      .or(this.forbidden())
      .first()
      .waitFor({ timeout: T.nav });
  }
}
