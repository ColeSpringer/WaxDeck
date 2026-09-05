// Playlists: the list, and one playlist's own screen.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickThrough, dragOnto, typeInto } from '../gestures';

export class Playlists extends Surface {
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

  /// The playlist screen's one overflow, and the export verbs behind it.
  overflow(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistOverflow));
  }

  exportNsp(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistExportNsp));
  }

  /// The dialog listing what an NSP export would drop.
  exportNspLoss(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistExportNspLoss));
  }

  /// One gap's row inside that dialog, by position.
  exportNspLossRow(index: number): Locator {
    return this.ctx.page.locator(
      sem(SemanticsIds.playlistExportNspLossRow(index)),
    );
  }

  exportNspProceed(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistExportNspProceed));
  }

  /// The copy button on whichever export document is on screen.
  exportCopy(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistExportCopy));
  }

  /// Open the overflow and take one of its verbs, settling on whatever
  /// that verb puts on screen.
  ///
  /// `chooseFromMenu` and not a second `clickThrough`: that one re-clicks
  /// its trigger whenever the destination is missing, and on a retry the
  /// click lands on the modal barrier and closes the menu the last
  /// attempt opened. It also waits for the menu's rect to come to rest,
  /// which is what stops a menu repositioning near a screen edge from
  /// taking the row underneath the one aimed at.
  async fromOverflow(verb: Locator, showing: Locator): Promise<void> {
    await chooseFromMenu(this.overflow(), verb, showing);
  }

  /// The synced-playlist settings sheet and its controls.
  syncSettings(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncSettings));
  }

  syncSheet(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncSheet));
  }

  syncUrl(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncUrl));
  }

  syncSave(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncSave));
  }

  syncNow(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncNow));
  }

  syncPreviewButton(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncPreview));
  }

  syncPreviewDialog(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncPreviewDialog));
  }

  syncChip(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncChip));
  }

  syncArm(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncArm));
  }

  syncSource(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncSource));
  }

  syncPayload(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncPayload));
  }

  syncMode(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playlistSyncMode));
  }

  async openSyncSheet(): Promise<void> {
    await this.fromOverflow(this.syncSettings(), this.syncSheet());
  }

  /// Bind the open sheet to a pasted export: pick the matched arm, name
  /// the format, paste, save. The bound-state verbs are what "saved"
  /// looks like.
  ///
  /// The arm pick settles on the source chooser, which the live arm
  /// does not draw. The format pick settles on nothing, deliberately:
  /// `chooseFromMenu` treats a visible `settled` as "already done" and
  /// returns without picking, and every control this pick reveals is on
  /// screen before it - so the menu closing is the only honest signal
  /// that the row was taken.
  async bindExport(source: string, payload: string): Promise<void> {
    const page = this.ctx.page;
    await chooseFromMenu(
      this.syncArm(),
      page.locator(sem(SemanticsIds.playlistSyncArmOption('matched'))),
      this.syncSource(),
    );
    await chooseFromMenu(
      this.syncSource(),
      page.locator(sem(SemanticsIds.playlistSyncSourceOption(source))),
    );
    await typeInto(page, this.syncPayload(), payload);
    await this.syncSave().click();
    await this.syncNow().waitFor({ timeout: T.action });
  }

  /// Flip the mode on the open sheet and save. On a bound playlist this
  /// is the settings-only re-save: nothing about the binding but its
  /// settings is resent.
  async saveSyncMode(mode: string): Promise<void> {
    await chooseFromMenu(
      this.syncMode(),
      this.ctx.page.locator(sem(SemanticsIds.playlistSyncModeOption(mode))),
    );
    await this.syncSave().click();
  }

  /// Type a source URL into the open sheet and save; the sheet answers
  /// with the bound-state verbs, which is what "saved" looks like.
  async bindSource(url: string): Promise<void> {
    await typeInto(this.ctx.page, this.syncUrl(), url);
    await this.syncSave().click();
    await this.syncNow().waitFor({ timeout: T.action });
  }

  /// Dismiss the topmost modal (the sheet, or a dialog above it)
  /// through its barrier's own Dismiss control, which is what the
  /// scrim exposes to assistive tech - steadier than Escape, which not
  /// every modal route binds. A retried unit around what dismissal
  /// should reveal, like every other dismissal in the driver: a click
  /// over the canvas landing during a rebuild is silently swallowed.
  async dismissSheet(showing: Locator): Promise<void> {
    await clickThrough(
      this.ctx.page.getByRole('button', { name: 'Dismiss' }).first(),
      showing,
    );
  }
}
