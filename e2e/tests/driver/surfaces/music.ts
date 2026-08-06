// The music domain: the hub, the indexes it opens, and a listing.

import { Locator } from '@playwright/test';
import {
  SEMANTICS_ATTRIBUTE,
  SemanticsIds,
  SemanticsIdPrefixes,
  sem,
  semPrefix,
} from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { clickThrough } from '../gestures';

/// The dimensions the hub offers, which are also the index locations.
export type MusicDimension = 'artists' | 'albums' | 'tracks' | 'genres' | 'years';

export class Music {
  constructor(private readonly ctx: Ctx) {}

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

  /// Open a bucket, which is a location of its own - the point being
  /// that a stranger can be sent to it.
  async openBucket(nth = 0): Promise<void> {
    await clickThrough(this.bucket(nth), this.entry(0));
  }

  /// The A-to-Z rail, drawn only beside an index that is actually in
  /// alphabetical order.
  rail(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.indexRail));
  }

  /// The A-to-Z chip, which is also the only one of the pair that
  /// carries an identifier.
  sort(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.indexSort));
  }

  /// Switch the index to biggest-first, which is a listing of its own
  /// with its own cursor space.
  ///
  /// By its label, not by an identifier: the chip row publishes one only
  /// on the A-to-Z chip, so this is the "no id exists" case the copy
  /// rule allows a driver - and it is the driver rather than five specs
  /// that owns the string.
  async sortByCount(): Promise<void> {
    await this.ctx.page.getByRole('button', { name: 'Most items' }).click();
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

  /// Open an item, which starts it playing.
  async play(pid: string): Promise<void> {
    await clickThrough(
      this.item(pid),
      this.ctx.page.locator(sem(SemanticsIds.playerToggle)),
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
    // The registry's prefix covers every item row, not only tracks, so a
    // caller that means one medium filters by pid type here rather than
    // spelling `item-tr-` into a selector - a literal the registry could
    // not rename.
    return type === undefined ? pids : pids.filter((pid) => pid.startsWith(`${type}-`));
  }
}
