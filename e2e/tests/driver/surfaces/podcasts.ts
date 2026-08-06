// Podcasts: the hub, a show, and its episodes.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { clickInView, clickThrough, typeInto } from '../gestures';

export class Podcasts {
  constructor(private readonly ctx: Ctx) {}

  add(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.podcastAdd));
  }

  /// A show's tile on the hub.
  show(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.podcast(pid)));
  }

  /// The follow control the show screen's header draws, and the hub does
  /// not. Arrival on a show is gated on this rather than on a row: the
  /// hub's shelves carry the same episode identifiers, and a gesture
  /// that skips its click when the destination already shows would then
  /// never leave the hub.
  unsubscribe(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.podcastUnsubscribe));
  }

  episode(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.episode(pid)));
  }

  episodeFetch(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.episodeFetch(pid)));
  }

  episodeInfo(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.episodeInfo(pid)));
  }

  /// Subscribe through the real add dialog.
  ///
  /// The open retries as a unit: a click over canvas can be swallowed
  /// while Flutter's handlers are still attaching, and a swallowed click
  /// here means the dialog never appears at all.
  async subscribeViaDialog(feedUrl: string): Promise<void> {
    const page = this.ctx.page;
    const confirm = page.locator(sem(SemanticsIds.podcastSubscribeConfirm));
    await clickThrough(this.add(), confirm);
    await typeInto(page, page.getByRole('textbox', { name: 'Feed or channel URL' }), feedUrl);
    await confirm.click();
  }

  /// Open a show from the hub.
  async openShow(pid: string): Promise<void> {
    await clickThrough(this.show(pid), this.unsubscribe());
  }

  /// Open an episode's own screen, as a retried unit.
  async openEpisodeInfo(pid: string, shows: Locator): Promise<void> {
    await clickThrough(this.episodeInfo(pid), shows);
  }

  /// Play an episode from its row.
  ///
  /// clickInView, not clickThrough: an episode row sits directly under
  /// the filter chips, and a forced click against a rect read while the
  /// list was still settling lands on a chip instead. Choosing
  /// "Downloaded" there removes the episode the click was aimed at, so
  /// every retry then clicks a row that is no longer in the list.
  async playEpisode(pid: string): Promise<void> {
    const page = this.ctx.page;
    await clickInView(page, this.episode(pid), {
      // The list scrolls under a fixed header, so a row past the first
      // is below the fold; the search field is a stable place inside the
      // same scroll view to put the cursor before wheeling.
      surface: page.locator(sem(SemanticsIds.showEpisodeSearch)),
      settled: page.locator(sem(SemanticsIds.playerToggle)),
    });
    await page.locator(sem(SemanticsIds.playerToggle)).waitFor({ timeout: T.nav });
  }

  /// Unsubscribe, keeping the files the server already fetched.
  async unsubscribeKeepingFiles(): Promise<void> {
    const page = this.ctx.page;
    const keep = page.locator(sem(SemanticsIds.unsubscribeKeepFiles));
    await clickThrough(this.unsubscribe(), keep);
    await keep.click();
    await page.locator(sem(SemanticsIds.podcastSubscribe)).waitFor({ timeout: T.nav });
  }

  /// The app's own back control, which on a show screen returns to the
  /// hub. Not the player's - that one is a collapse chevron and a name
  /// match walks past the player onto the screen underneath.
  async back(settledOn: Locator): Promise<void> {
    await clickThrough(
      this.ctx.page.getByRole('button', { name: 'Back' }).first(),
      settledOn,
    );
  }

  /// Text on the screen, for show notes and other prose.
  text(what: string | RegExp): Locator {
    return this.ctx.page.getByText(what).first();
  }
}
