// The queue: a screen of its own, reached from the player.

import { Locator } from '@playwright/test';
import {
  SemanticsIds,
  SemanticsIdPrefixes,
  sem,
  semPrefix,
} from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { clickInView } from '../gestures';

export class Queue {
  constructor(private readonly ctx: Ctx) {}

  screen(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.queueScreen));
  }

  shuffle(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.queueShuffle));
  }

  clear(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.queueClear));
  }

  /// The drag handles the entries after the current one carry.
  dragHandles(): Locator {
    return this.ctx.page.locator(semPrefix(SemanticsIdPrefixes.queueEntryDrag));
  }

  entry(queueId: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.queueEntry(queueId)));
  }

  /// Open the queue from the player.
  ///
  /// From the player rather than from the deck bar, whose control at
  /// this width toggles a panel instead: over the shell there is no
  /// panel slot to use, so the player's own control pushes the queue's
  /// screen, which is the surface worth testing. Not by location either
  /// - since the path-URL flip that is a real page load, and it would
  /// restart the app and take the queue with it.
  ///
  /// clickInView rather than clickThrough, because this control is one
  /// small glyph in a row of them on a screen that animates in from
  /// below: a forced click against a rect read a moment earlier lands on
  /// the neighbour, and the neighbour is Discover, whose menu then
  /// covers the queue button so every retry clicks the barrier instead.
  /// Seen once. clickInView re-reads the box each attempt and refuses to
  /// click until it is fully in view.
  async openFromPlayer(): Promise<void> {
    const page = this.ctx.page;
    await clickInView(page, page.locator(sem(SemanticsIds.playerQueue)), {
      settled: this.shuffle(),
    });
    await this.shuffle().waitFor({ timeout: T.nav });
  }

  /// Text the queue surface is showing - where it is playing from, or
  /// what it says when there is nothing in it. Neither carries an
  /// identifier, so the driver finds it and the spec judges the words.
  text(what: string | RegExp): Locator {
    return this.ctx.page.getByText(what).first();
  }
}
