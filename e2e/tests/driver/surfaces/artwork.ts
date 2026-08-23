// The artwork manager: the slot grid on the metadata editor, and setting
// a cover from a file the way a person does.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';

export class Artwork extends Surface {
  /// The metadata editor's own location for one item, which is where the
  /// slot grid lives. A deep link the app itself mints.
  editorLocation(pid: string): string {
    return `/metadata/${pid}`;
  }

  /// One slot's tile. Its accessible name is what it holds - the format
  /// and pixel size the catalog stored - so a spec asserts that rather
  /// than reading it out of a control.
  slot(role: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.artSlot(role)));
  }

  /// The control that opens the file chooser for one slot.
  setSlot(role: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.artSlotSet(role)));
  }

  /// What a tile says it holds, by accessible name. A slot draws as one
  /// image with a spoken description rather than as text nodes.
  slotNamed(name: RegExp): Locator {
    return this.ctx.page.getByRole('img', { name });
  }

  /// Set a slot's cover through the real chooser.
  ///
  /// The chooser event is armed before the click that opens it, for the
  /// reason the uploads surface gives: a native dialog is not a page
  /// element and there is no second chance once it has opened.
  async setCoverFromFile(role: string, file: string): Promise<void> {
    const page = this.ctx.page;
    const control = this.setSlot(role);
    await control.waitFor({ timeout: T.nav });
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      control.click({ force: true }),
    ]);
    await chooser.setFiles([file]);
  }
}
