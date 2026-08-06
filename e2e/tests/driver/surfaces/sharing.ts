// Share links: the list under settings, and what makes one.

import { Locator } from '@playwright/test';
import {
  SemanticsIds,
  SemanticsIdPrefixes,
  sem,
  semPrefix,
} from '../../semantics-ids';
import { Ctx } from '../context';
import { clickThrough } from '../gestures';

export class Sharing {
  constructor(private readonly ctx: Ctx) {}

  /// The shares list, however this account's happens to be drawn.
  ///
  /// One locator for the empty state and the rows together, because
  /// which one a visitor gets is a property of their account and not of
  /// the screen: what is under test is that the location resolves to the
  /// list at all.
  list(): Locator {
    return this.empty().or(this.anyRow());
  }

  empty(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.sharesEmpty));
  }

  anyRow(): Locator {
    return this.ctx.page.locator(semPrefix(SemanticsIdPrefixes.shareRow)).first();
  }

  row(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shareRow(pid)));
  }

  revoke(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shareRevoke(pid)));
  }

  copy(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shareCopy(pid)));
  }

  /// Open the shares list from the Account section's own row, which goes
  /// rather than pushes now that the location is declared beneath
  /// settings.
  async openFromSettings(): Promise<void> {
    await clickThrough(
      this.ctx.page.locator(sem(SemanticsIds.openShareLinks)),
      this.list(),
    );
  }

  /// The share sheet a screen's own share control opens.
  createControl(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shareCreate));
  }

  allowDownload(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shareAllowDownload));
  }

  link(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.shareLink));
  }
}
