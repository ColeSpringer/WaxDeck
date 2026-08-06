// The player, and the deck bar it expands from.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickThrough } from '../gestures';

export class Player {
  constructor(private readonly ctx: Ctx) {}

  /// Play/pause. Also the marker that something is playing at all,
  /// which is why so many navigation steps settle on it.
  toggle(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerToggle));
  }

  /// The trim chip, which reports time actually saved once the session
  /// has seeked over lead silence. Positions stay honest, so this is the
  /// only quick proof that trimmed playback is not ordinary playback.
  trim(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerTrim));
  }

  speed(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerSpeed));
  }

  /// Wait until the player is up and holding something.
  async ready(): Promise<void> {
    await this.toggle().waitFor({ timeout: T.nav });
  }

  /// Choose a playback rate from the speed sheet. One tap to any rate,
  /// where the cycling button this replaced could only walk to it.
  ///
  /// Through `chooseFromMenu` rather than a bare forced click: the sheet
  /// is a trigger that opens a list and dismisses on choosing, which is
  /// a menu in every way that matters here, and what that gesture brings
  /// is the rect-at-rest check. A forced click dispatches at whatever
  /// rect the semantics overlay held a frame earlier, which near a
  /// screen edge lands one row off - the difference between 1.5x and
  /// whatever sits beside it.
  async setSpeed(percent: number): Promise<void> {
    await chooseFromMenu(
      this.speed(),
      this.ctx.page.locator(sem(SemanticsIds.playerSpeedPreset(percent))),
    );
  }

  /// The player's own way out. Not a "Back" button: it is a collapse
  /// chevron since the scaffold rebuild, and a name match walks past the
  /// player onto the screen underneath - which is how a spec came to pop
  /// the wrong screen.
  async collapse(settledOn: Locator): Promise<void> {
    await clickThrough(this.ctx.page.locator(sem(SemanticsIds.playerBack)), settledOn);
  }

  /// A control on the player, by identifier, for the surfaces that have
  /// not earned a method yet.
  control(id: string): Locator {
    return this.ctx.page.locator(sem(id));
  }

  /// Pick a value from a menu the player owns.
  async choose(trigger: Locator, item: Locator, settled?: Locator): Promise<void> {
    await chooseFromMenu(trigger, item, settled);
  }
}
