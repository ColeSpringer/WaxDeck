// Playlists: the list, and one playlist's own screen.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { clickThrough, dragOnto, typeInto } from '../gestures';

export class Playlists {
  constructor(private readonly ctx: Ctx) {}

  add(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistAdd));
  }

  /// One playlist's row on the list.
  row(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlist(pid)));
  }

  /// A row inside an open playlist, by position.
  entry(index: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistEntry(index)));
  }

  entryRemove(index: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistEntryRemove(index)));
  }

  entryDrag(index: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistEntryDrag(index)));
  }

  overflow(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistOverflow));
  }

  /// Open a playlist from the list. Settles on its first row, which is
  /// what the list itself never draws.
  async open(pid: string): Promise<void> {
    await clickThrough(this.row(pid), this.entry(0));
  }

  /// Open a playlist and wait for whatever it should be showing - an
  /// empty state, a rule summary, the row that adds to it.
  async openShowing(pid: string, showing: Locator): Promise<void> {
    await clickThrough(this.row(pid), showing);
  }

  nameField(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistNameField));
  }

  /// Make a playlist through the real dialog. The kind chip is clicked
  /// twice over: `clickThrough` opens the dialog and settles when the
  /// chip appears, and the chip itself still has to be chosen.
  async create(kind: 'smart' | 'static', name: string): Promise<void> {
    const page = this.ctx.page;
    const chip = page.locator(sem(SemanticsIds.playlistCreateKind(kind)));
    await clickThrough(this.add(), chip);
    await chip.click();
    await typeInto(page, this.nameField(), name);
    await page.locator(sem(SemanticsIds.playlistCreateConfirm)).click();
  }

  /// Make a list from the add-to-playlist sheet, which is what the
  /// player's overflow opens.
  async createFromSheet(name: string): Promise<void> {
    const page = this.ctx.page;
    await page.locator(sem(SemanticsIds.addToPlaylistNew)).click();
    await typeInto(page, this.nameField(), name);
    await page.locator(sem(SemanticsIds.playlistCreateConfirm)).click();
  }

  /// The row that adds to a manual list without leaving the page being
  /// built, and the first thing it finds.
  addField(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistAddField));
  }

  /// Search from the list's own row and take the first hit.
  async addByTitle(title: string): Promise<void> {
    const page = this.ctx.page;
    await typeInto(page, this.addField(), title);
    const hit = page.locator(sem(SemanticsIds.playlistAddResult(0)));
    await hit.waitFor({ timeout: T.assert });
    await hit.click();
  }

  /// Move one row above another, by its drag handle.
  async reorder(from: number, to: number): Promise<void> {
    await this.entryDrag(from).waitFor({ timeout: T.assert });
    await dragOnto(this.ctx.page, this.entryDrag(from), this.entryDrag(to));
  }

  /// The rule editor a smart list opens into.
  ruleAddCondition(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.ruleAddCondition));
  }

  rulePreview(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.rulePreviewTotal));
  }

  ruleSave(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.ruleSave));
  }

  ruleSummary(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistRuleSummary));
  }

  /// A playlist screen's header, by the line it announces.
  ///
  /// The header merges its subtree into one node, so what a screen
  /// reader hears is that line rather than a text node of its own -
  /// which is why this is a role-and-name match and not `text`.
  header(name: string | RegExp): Locator {
    return this.ctx.page.getByRole('banner', { name });
  }

  /// A control on a playlist's screen that has its own identifier - the
  /// rename field, the export rows, the visibility switch.
  control(id: string): Locator {
    return this.ctx.page.locator(sem(id));
  }

  /// Text on the list or on a playlist - a name, a rule summary. Names
  /// are prose the app draws from the account's own data rather than
  /// controls, so the spec supplies the words.
  text(what: string | RegExp): Locator {
    return this.ctx.page.getByText(what).first();
  }
}
