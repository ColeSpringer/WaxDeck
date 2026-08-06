// Casting: the device picker, and the connection check behind it.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickInView, clickThrough } from '../gestures';

export class Cast {
  constructor(private readonly ctx: Ctx) {}

  picker(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.picker));
  }

  /// The row for the device the visitor is already on, which says so
  /// rather than offering a trip to where they are.
  thisDevice(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.pickerThisDevice));
  }

  /// The connection check: a cast that fails is silent, and this is the
  /// surface that says why.
  preflight(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.preflight));
  }

  base(index: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.preflightBase(index)));
  }

  /// Open the picker from the deck bar's cast control.
  async openPicker(): Promise<void> {
    await clickThrough(
      this.ctx.page.locator(sem(SemanticsIds.deckCast)),
      this.picker(),
    );
  }

  /// Open the picker from the player's own devices control.
  ///
  /// Opened on its own terms and then left standing. Not
  /// `chooseFromMenu`: that gesture re-clicks its trigger whenever the
  /// row it wants is missing, and here the trigger is behind the sheet's
  /// own modal barrier - so a picker still fetching its sessions would
  /// be closed by the very retry waiting on it.
  async openFromPlayer(): Promise<void> {
    await clickThrough(
      this.ctx.page.locator(sem(SemanticsIds.playerDevices)),
      this.picker(),
    );
  }

  /// Another client's session, as the picker lists it.
  session(id: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.session(id)));
  }

  /// The remote screen's transport, which drives the other client's real
  /// engine.
  remoteToggle(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.remoteToggle));
  }

  /// Take control of a session listed in the picker.
  ///
  /// "Playing elsewhere" is the last section in the sheet, so on a short
  /// window the row sits below the fold and the click is refused as
  /// outside the viewport. Scrolled and clicked as one unit against a
  /// list that relists whenever any session changes - and the other
  /// client plays throughout; the remote screen is what proves the row
  /// was hit.
  async takeOver(sessionId: string): Promise<void> {
    const page = this.ctx.page;
    const row = this.session(sessionId);
    await row.waitFor({ timeout: T.assert });
    await clickInView(page, row, {
      surface: this.picker(),
      settled: this.remoteToggle(),
    });
  }

  /// Press the remote transport.
  ///
  /// Nothing to settle on: the toggle's own label is whatever the
  /// session last reported, so it cannot say which press produced it.
  /// What the press did is asserted on the server side, where the
  /// session state is republished.
  async pressRemote(): Promise<void> {
    await clickInView(this.ctx.page, this.remoteToggle());
  }

  /// Run the connection check, one level into the picker's overflow.
  ///
  /// `chooseFromMenu`, not `clickThrough`: that gesture re-clicks its
  /// trigger while it waits, which is right for a navigation and wrong
  /// for a menu - under a loaded stack the second click closed the menu
  /// the first had opened, and a third dismissed the sheet under it. A
  /// single un-retried click was not the answer either, and failed about
  /// half the time under a full parallel run.
  async runCheck(): Promise<void> {
    await chooseFromMenu(
      this.ctx.page.locator(sem(SemanticsIds.pickerOverflow)),
      this.ctx.page.locator(sem(SemanticsIds.pickerCheck)),
      this.preflight(),
    );
  }
}
