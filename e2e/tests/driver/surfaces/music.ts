// The music domain: the hub, the indexes it opens, and a listing.

import { expect, Locator } from '@playwright/test';
import {
  SEMANTICS_ATTRIBUTE,
  SemanticsIds,
  SemanticsIdPrefixes,
  sem,
  semPrefix,
} from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickThrough } from '../gestures';

/// The dimensions the hub offers, which are also the index locations.
export type MusicDimension = 'artists' | 'albums' | 'tracks' | 'genres' | 'years';

export class Music extends Surface {
  /// A tile on the music hub: the way into one dimension's index.
  tile(dimension: MusicDimension): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.musicTile(dimension)));
  }

  /// Open a dimension's index from the hub.
  async openIndex(dimension: MusicDimension): Promise<void> {
    await clickThrough(this.tile(dimension), this.bucket(0));
  }

  /// A row in an index: an artist, an album, a genre, a year.
  bucket(nth: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.indexBucket(nth)));
  }

  /// A row inside an opened bucket.
  entry(nth: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.indexItem(nth)));
  }

  /// How many rows an opened bucket is showing.
  ///
  /// For a spec whose subject is what happens to the queue afterwards:
  /// playing a row queues the whole listing, so this is what a mix
  /// landing behind it has to be counted against rather than assumed.
  async entryCount(): Promise<number> {
    const rows = this.ctx.page.locator(semPrefix(SemanticsIdPrefixes.indexItem));
    await rows.first().waitFor({ timeout: T.nav });
    return rows.count();
  }

  /// Open a bucket, which is a location of its own - the point being
  /// that a stranger can be sent to it.
  async openBucket(nth = 0): Promise<void> {
    await clickThrough(this.bucket(nth), this.entry(0));
  }

  /// The verbs an entity screen's header carries, which a filtered
  /// listing at the same location never had.
  entityPlay(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.entityPlay));
  }

  entityShuffle(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.entityShuffle));
  }

  /// Open an index bucket as the entity it names, rather than as a list.
  /// Settles on the header's verbs, which is what tells the two apart.
  async openEntity(nth = 0): Promise<void> {
    await clickThrough(this.bucket(nth), this.entityShuffle());
  }

  /// Start an entity playing from its header. Play lands in the dock,
  /// so the deck bar is what proves the click took; a spec that needs
  /// the full player expands it with `player.ready()`.
  async playEntity(how: 'play' | 'shuffle' = 'shuffle'): Promise<void> {
    await clickThrough(
      how === 'shuffle' ? this.entityShuffle() : this.entityPlay(),
      this.ctx.page.locator(sem(SemanticsIds.deckBar)),
    );
  }

  /// Play one row of an opened bucket, which queues what it belongs to.
  /// Settles on the deck bar, so with something already playing the
  /// click is skipped - a repeat play needs its own signal.
  async playEntry(nth = 0): Promise<void> {
    await clickThrough(
      this.entry(nth),
      this.ctx.page.locator(sem(SemanticsIds.deckBar)),
    );
  }

  /// The play count beside one album row's running time, drawn only on
  /// a track the reading account has finished at least once.
  trackPlays(nth: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.albumTrackPlays(nth)));
  }

  /// Open one album row's overflow and pick the facts sheet from it.
  /// Settles on the sheet's own play row, which nothing else draws.
  async openTrackFacts(nth: number): Promise<void> {
    await chooseFromMenu(
      this.ctx.page.locator(sem(SemanticsIds.albumTrackMore(nth))),
      this.ctx.page.locator(sem(SemanticsIds.itemMenuDetails)),
      this.ctx.page.locator(sem(SemanticsIds.itemFactsRow('plays'))),
    );
  }

  /// The entity header's overflow, and the pin row inside it.
  entityOverflow(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.entityOverflow));
  }

  entityPin(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.entityPin));
  }

  /// Pin or unpin the entity screen that is open, which the caller names
  /// by pid rather than this parsing it back out of the URL.
  ///
  /// `chooseFromMenu` rather than `clickThrough`: a retried click on an
  /// overflow trigger lands on the modal barrier and closes the menu the
  /// previous attempt opened.
  ///
  /// The row produces nothing here, so the gesture falls back to the
  /// menu going away - which a dismissal satisfies too. The preference
  /// document is the only honest proof, and reading it first keeps a
  /// landed toggle from being fired back the other way.
  async togglePin(pid: string): Promise<void> {
    const pinned = async () =>
      (((await this.ctx.api.get('/users/me/prefs')).pinned ?? []) as string[]).includes(pid);
    const want = !(await pinned());
    await expect(async () => {
      if ((await pinned()) === want) return;
      await chooseFromMenu(this.entityOverflow(), this.entityPin());
      await expect.poll(pinned, { timeout: T.assert }).toBe(want);
    }).toPass({ timeout: T.fetch });
  }

  /// The release identity block, drawn only where the album entity
  /// carries one of the five edition columns.
  albumIdentity(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.albumIdentity));
  }

  /// The A-to-Z rail, drawn only beside an index that is actually in
  /// alphabetical order.
  rail(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.indexRail));
  }

  /// Switch the index to biggest-first, a listing of its own with its
  /// own cursor space.
  async sortByCount(): Promise<void> {
    await this.ctx.page.locator(sem(SemanticsIds.indexSortCount)).click();
  }

  /// Any item row on screen, for a spec that means "some track" rather
  /// than a particular one.
  anyItem(): Locator {
    return this.ctx.page.locator(semPrefix(SemanticsIdPrefixes.item)).first();
  }

  /// One item row by pid, on whatever listing is showing.
  item(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.item(pid)));
  }

  /// Open an item, which starts it playing in the dock. Settles on the
  /// deck bar, so a second play while something already plays needs its
  /// own signal - the bar is already up and the click would be skipped.
  async play(pid: string): Promise<void> {
    await clickThrough(
      this.item(pid),
      this.ctx.page.locator(sem(SemanticsIds.deckBar)),
    );
  }

  /// The pids the listing on screen is showing, in its own order.
  async visiblePids(type?: string): Promise<string[]> {
    const rows = this.ctx.page.locator(semPrefix(SemanticsIdPrefixes.item));
    await rows.first().waitFor({ timeout: T.nav });
    const ids = (await rows.evaluateAll(
      (els, attribute) => els.map((e) => e.getAttribute(attribute) ?? ''),
      SEMANTICS_ATTRIBUTE,
    )) as string[];
    const pids = ids.map((id) => id.slice(SemanticsIdPrefixes.item.length));
    // The prefix covers every item row, not only tracks, so a caller
    // that means one medium filters here rather than spelling `item-tr-`
    // into a selector the registry could not rename.
    return type === undefined ? pids : pids.filter((pid) => pid.startsWith(`${type}-`));
  }
}
