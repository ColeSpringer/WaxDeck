// Search: one field throughout, wherever the layout puts it.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { clickThrough, typeInto } from '../gestures';

export class Search {
  constructor(private readonly ctx: Ctx) {}

  /// The field itself. At sidebar width it lives in the chrome header
  /// and the search screen draws none of its own while it is showing,
  /// which is what makes clicking it keep the caret.
  field(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.searchField));
  }

  filter(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.searchFilter(name)));
  }

  hit(group: string, nth: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.searchHit(group, nth)));
  }

  /// Open the search screen from wherever the app is.
  async open(): Promise<void> {
    await clickThrough(this.field(), this.filter('all'));
  }

  /// Type a query and wait for the group that should answer it.
  async run(query: string, expecting: string): Promise<void> {
    const page = this.ctx.page;
    await typeInto(page, this.field(), query);
    await this.hit(expecting, 0).waitFor({ timeout: T.nav });
  }

  /// Narrow to one group. A chip that covers nothing says so rather than
  /// showing an empty page with the other groups' hits behind it - what
  /// it says is the spec's assertion.
  async narrowTo(name: string): Promise<void> {
    await this.filter(name).click();
  }

  /// What the screen shows for a filter that matches nothing. By its
  /// copy, because the empty state publishes no identifier - and the
  /// copy is the point: the difference between a screen that explains
  /// itself and a blank pane is invisible to a count of hits.
  emptyState(): Locator {
    return this.ctx.page.getByText(/Nothing for/);
  }

  /// Open a hit. Retried as a unit, because Flutter web swallows a click
  /// while its handlers are still attaching and a swallowed one here
  /// means the player never opens at all.
  async play(group: string, nth: number): Promise<void> {
    await clickThrough(
      this.hit(group, nth),
      this.ctx.page.locator(sem(SemanticsIds.playerToggle)),
    );
  }
}
