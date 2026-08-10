// The review queue: the keyboard-first curation surface.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { clickThrough, typeInto } from '../gestures';

export class Review extends Surface {
  row(entryId: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.reviewRow(entryId)));
  }

  /// The as-is decision, which is what an entry with no candidates
  /// offers - and, being on the entry pane rather than the queue, what
  /// tells the two apart.
  asIs(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.reviewAsIs));
  }

  /// The empty state a declined entry draws in place of candidates.
  skippedIdentification(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.reviewIdentifySkipped));
  }

  /// Type what to search for instead of what an entry's files claim,
  /// and run the search. Blank values clear a stored override.
  async identifyAs(values: {
    artist?: string;
    album?: string;
    title?: string;
  }): Promise<void> {
    const page = this.ctx.page;
    const group = page.locator(sem(SemanticsIds.reviewIdentifyGroup));
    await group.waitFor({ timeout: T.nav });
    // Already open when an override is stored, so the disclosure is
    // only pressed when it has to be.
    const artist = page.locator(sem(SemanticsIds.reviewIdentifyField('artist')));
    if (!(await artist.isVisible())) {
      await clickThrough(page.locator(sem(SemanticsIds.reviewIdentifyToggle)), artist);
    }
    // typeInto, not fill: the editable hangs off the identified node
    // and binds asynchronously - see gestures.ts.
    for (const [name, value] of Object.entries(values)) {
      await typeInto(page, page.locator(sem(SemanticsIds.reviewIdentifyField(name))), value ?? '');
    }
    await page.locator(sem(SemanticsIds.reviewIdentifySubmit)).click({ force: true });
  }

  /// Open one entry and wait for its pane.
  async open(entryId: string): Promise<void> {
    await this.row(entryId).click({ force: true });
    await this.asIs().waitFor({ timeout: T.assert });
  }

  /// A key the queue binds. Escape closes the pane, `e` reopens the
  /// entry the cursor is on.
  async press(key: string): Promise<void> {
    await this.ctx.page.keyboard.press(key);
  }
}
