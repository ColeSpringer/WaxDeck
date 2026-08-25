// Podcasts: the hub, a show, and its episodes.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickInView, clickThrough, typeInto } from '../gestures';

export class Podcasts extends Surface {
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

  /// Subscribe through the real add dialog, by feed URL.
  ///
  /// The dialog opens on a directory search now, so the URL path is a
  /// disclosure under it: open the dialog, open the disclosure, then
  /// type. Opening the dialog retries as a unit, because a click over
  /// canvas can be swallowed while Flutter's handlers are still
  /// attaching.
  ///
  /// The disclosure does not, and must not: `clickThrough` re-fires its
  /// trigger on every attempt the goal is missing, and this trigger is a
  /// toggle - one slow frame and the retry closes what the last attempt
  /// opened, and every attempt after that is a coin flip. Same reason
  /// `chooseFromMenu` exists. One click, then wait for what it reveals.
  async subscribeViaDialog(feedUrl: string): Promise<void> {
    const page = this.ctx.page;
    const byUrl = page.locator(sem(SemanticsIds.podcastAddByUrl));
    const confirm = page.locator(sem(SemanticsIds.podcastSubscribeConfirm));
    await clickThrough(this.add(), byUrl);
    await byUrl.click({ timeout: T.step });
    await confirm.waitFor({ timeout: T.nav });
    await typeInto(page, page.getByRole('textbox', { name: 'Feed or channel URL' }), feedUrl);
    await confirm.click();
  }

  /// Open a show from the hub.
  async openShow(pid: string): Promise<void> {
    await clickThrough(this.show(pid), this.unsubscribe());
  }

  /// A show screen's shareable location.
  showLocation(pid: string): string {
    return `/podcasts/${pid}`;
  }

  /// The show screen's own menu.
  overflow(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.showOverflow));
  }

  /// Open the show cover manager through the menu's curator-only Set
  /// cover row; settled is a slot the manager draws.
  async openCoverManager(settled: Locator): Promise<void> {
    await chooseFromMenu(
      this.overflow(),
      this.ctx.page.locator(sem(SemanticsIds.showSetCover)),
      settled,
    );
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
}
