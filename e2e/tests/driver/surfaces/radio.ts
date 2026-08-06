// Radio: the hub, the dial, and the deck bar a live stream drives.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { clickInView, clickThrough } from '../gestures';

export class Radio {
  constructor(private readonly ctx: Ctx) {}

  hub(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioHub));
  }

  /// One station's row in the library.
  station(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radio(pid)));
  }

  /// The band under the needle. Drawn only once something is pinned: a
  /// dial with nothing on it is a stripe of chrome.
  dial(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioDial));
  }

  /// The dial's own control, which names what it will do.
  tune(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.radioTune));
  }

  /// The hub's own search control, which is its share of compact search:
  /// the shell owns no top app bar, so every rebuilt screen brings the
  /// control with it.
  searchAction(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.searchAction));
  }

  /// Pin a station, which is what brings the dial into existence.
  async pin(pid: string): Promise<void> {
    await clickThrough(
      this.ctx.page.locator(sem(SemanticsIds.radioFavorite(pid))),
      this.dial(),
    );
  }

  /// Unpin it. Forced, and with nothing to settle on here: what the
  /// unpin did - the dial going away, the stored list clearing - is the
  /// spec's assertion.
  async unpin(pid: string): Promise<void> {
    await this.ctx.page
      .locator(sem(SemanticsIds.radioFavorite(pid)))
      .click({ force: true });
  }

  /// Tune the dial in, which takes the engine.
  ///
  /// clickInView: the dial has only just appeared and is settling into
  /// place, so its control is a moving target for a single forced click.
  /// The deck bar is what proves the tune took.
  async tuneIn(): Promise<void> {
    const bar = this.deckBar();
    await clickInView(this.ctx.page, this.tune(), { settled: bar });
    await bar.waitFor({ timeout: T.nav });
  }

  /// The deck bar a live stream drives.
  ///
  /// What a station is called lives in the bar's accessible name rather
  /// than in its text: the title block is excluded from semantics so the
  /// bar announces once instead of re-reading its own elapsed time at
  /// every tick.
  deckBar(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.deckBar));
  }

  /// The bar's star, which a station never has: per-user state does not
  /// exist for one, and a permanently greyed control reads as broken
  /// rather than as absent.
  deckStar(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.deckStar));
  }

  /// Stop the stream. Radio never enters the queue, so this puts the bar
  /// away entirely.
  async stop(): Promise<void> {
    await this.ctx.page.locator(sem(SemanticsIds.deckPlay)).click({ force: true });
  }

  /// The transport's own control, by the two true things it can say:
  /// stop (a paused live stream resumes at the live edge anyway, and the
  /// transport does not pretend otherwise), or tap-to-resume where the
  /// browser refused the programmatic start.
  transport(name: RegExp): Locator {
    return this.ctx.page.getByRole('button', { name }).first();
  }

  text(what: string | RegExp): Locator {
    return this.ctx.page.getByText(what).first();
  }
}
