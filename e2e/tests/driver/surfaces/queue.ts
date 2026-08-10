// The queue: a screen of its own, reached from the player.

import { expect, Locator } from '@playwright/test';
import {
  SemanticsIds,
  SemanticsIdPrefixes,
  SEMANTICS_ATTRIBUTE,
  sem,
  semPrefix,
} from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { clickInView, clickThrough, dragOnto, longPressOn } from '../gestures';

export class Queue extends Surface {
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

  /// Every up-next row's checkbox, which exists only while a set is
  /// picked - so its count is also how many rows the mode reaches.
  selectBoxes(): Locator {
    return this.ctx.page.locator(
      semPrefix(SemanticsIdPrefixes.queueEntrySelect),
    );
  }

  /// The verbs a picked set has.
  selectionRemove(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.queueSelectionRemove));
  }

  selectionTop(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.queueSelectionTop));
  }

  selectionClear(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.queueSelectionClear));
  }

  /// Start a selection on one up-next row, the way a hand does.
  async pick(queueId: string): Promise<void> {
    await longPressOn(this.ctx.page, this.entry(queueId));
  }

  /// End a selection with the key that ends it.
  async escape(): Promise<void> {
    await this.ctx.page.keyboard.press('Escape');
  }

  /// The queue id of the first row after the current entry.
  ///
  /// Read off its drag handle rather than guessed: queue ids are minted
  /// by the client and count up across a session, so the first up-next
  /// row is `q1` only on a queue nothing has been added to.
  async firstUpNextId(): Promise<string> {
    const handle = this.dragHandles().first();
    await handle.waitFor({ timeout: T.nav });
    const id = await handle.getAttribute(SEMANTICS_ATTRIBUTE);
    expect(id, 'the first up-next row carries a drag handle').toBeTruthy();
    return id!.slice(SemanticsIdPrefixes.queueEntryDrag.length);
  }

  /// The queue in the shell's right panel, which exists only where
  /// there is room for one beside what is being browsed.
  panel(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.panel));
  }

  /// The deck bar the panel opens from: the settle target for a
  /// gesture that must land back on the shell's chrome, like
  /// collapsing the player before [openPanel].
  deckBar(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.deckBar));
  }

  /// Open that panel from the deck bar, which is what toggles it at
  /// sidebar width.
  ///
  /// Not `clickThrough`, and the difference is that the control is a
  /// toggle: clickThrough re-clicks whenever the destination is not
  /// showing yet, and against a toggle the re-click closes the panel
  /// the first click opened - an oscillation that never settles on a
  /// loaded machine. So each attempt clicks only while the panel is
  /// absent, then gives it one step to appear.
  async openPanel(): Promise<void> {
    const panel = this.panel();
    await expect(async () => {
      if ((await panel.count()) === 0) {
        await this.ctx.page.locator(sem(SemanticsIds.deckQueue)).click();
      }
      await panel.waitFor({ timeout: T.step });
    }).toPass({ timeout: T.nav });
  }

  /// Drag a row onto the panel, which appends it to the queue.
  ///
  /// Pointer only by design, so this is the whole of the gesture's
  /// coverage over the real stack: there is no semantics node to click
  /// instead, because a drag publishes none.
  async dragOntoPanel(row: Locator): Promise<void> {
    await dragOnto(this.ctx.page, row, this.panel());
  }
}
