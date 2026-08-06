// The review queue: the keyboard-first curation surface.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';

export class Review {
  constructor(private readonly ctx: Ctx) {}

  row(entryId: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.reviewRow(entryId)));
  }

  /// The as-is decision, which is what an entry with no candidates
  /// offers - and, being on the entry pane rather than the queue, what
  /// tells the two apart.
  asIs(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.reviewAsIs));
  }

  approve(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.reviewApprove));
  }

  skip(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.reviewSkip));
  }

  filter(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.reviewFilter(name)));
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
