// Discovery: the instant mix, and the sonic surfaces beside it.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { clickThrough, clickToward } from '../gestures';

export class Discovery extends Surface {
  /// The Discover control on the player, which is where a mix starts.
  discover(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerDiscover));
  }

  /// A row of a scoped list - the mix's own items, the similar tracks.
  item(scope: string, nth: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.scopedItem(scope, nth)));
  }

  /// The chip reporting which engine answered. Since the rebuild onto
  /// the design system it is a labelled readout rather than a Material
  /// chip that announced itself as a checkbox - so the handle is
  /// generated and scoped to its screen, and what it says is matched as
  /// text: a plain labelled readout carries no role, so flutter puts its
  /// name in the node's text content and leaves aria-label off (a
  /// control's name would be the attribute).
  basis(scope: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.mixBasis(scope)));
  }

  /// Start an instant mix from whatever the player is holding.
  ///
  /// The confirm is retried on its own after being clicked through,
  /// because the sheet closes only once the mix came back: a swallowed
  /// click leaves it open with nothing on the way, and there is no other
  /// signal that the request was never made.
  async runInstantMix(): Promise<void> {
    const page = this.ctx.page;
    const mix = page.locator(sem(SemanticsIds.instantMix));
    const run = page.locator(sem(SemanticsIds.instantMixRun));
    await clickThrough(this.discover(), mix);
    await clickThrough(mix, run);
    await expect(async () => {
      await clickToward(run, { gone: run });
    }).toPass({ timeout: T.nav });
  }

  /// The "Open" on the message a mix landing behind a standing queue
  /// raises. The mix changes nothing on screen, so this is the only
  /// affordance it leaves.
  queueFromMessage(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.queueOpen));
  }

  /// List the tracks like whatever the player is holding.
  ///
  /// The list is pushed rather than played, so the settle target is the
  /// list's first row - which needs the seed to actually have
  /// neighbours, so callers prove that over the API first.
  async runSimilarTracks(): Promise<void> {
    const page = this.ctx.page;
    const similar = page.locator(sem(SemanticsIds.similarTracks));
    await clickThrough(this.discover(), similar);
    await clickThrough(similar, this.item('similar', 0));
  }
}
