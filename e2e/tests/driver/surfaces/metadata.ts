// The metadata editor, and the item-menu door listing rows open into
// it. The editor itself is one screen wherever it was opened from; the
// doors are per-surface (a row's kebab, a card's right click), so the
// spec opens the menu with the surface's own gesture and this surface
// takes it from the sheet to the editor.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { longPressOn, typeInto, wheelIntoReach } from '../gestures';

export class Metadata extends Surface {
  /// The editor screen, whichever surface opened it.
  editor(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.metadataEditor));
  }

  /// The refusal page the editor answers a non-curator with.
  forbidden(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.metadataForbidden));
  }

  /// The edit entry for one item on whichever row menu is open.
  editEntry(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.editMetadata(pid)));
  }

  /// From an open row menu into the editor: click the sheet's edit
  /// entry and wait for the editor screen (or the refusal, which is a
  /// real arrival too - the caller asserts which).
  async openEditorFromRow(pid: string): Promise<void> {
    await this.editEntry(pid).click({ timeout: T.step });
    await this.editor()
      .or(this.forbidden())
      .first()
      .waitFor({ timeout: T.nav });
  }

  /// One typed field on the item editor, wherever it is mounted - the
  /// standalone screen or the workbench's pane.
  itemField(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.metadataField(name)));
  }

  /// The editor's fetch button, which previews before anything lands.
  enrichButton(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.metadataEnrich));
  }

  /// The enrichment preview sheet and its two answers.
  previewSheet(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.enrichPreview));
  }

  previewApply(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.enrichPreviewApply));
  }

  previewCancel(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.enrichPreviewCancel));
  }

  /// The artist / release-group editor, served at /metadata/<ar-...>
  /// and /metadata/<rg-...>.
  entityEditor(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.entityEditor));
  }

  /// Cold-load the artist / release-group editor on one entity pid.
  async openEntityEditor(pid: string): Promise<void> {
    await this.ctx.page.goto(`/metadata/${pid}`);
    await this.entityEditor().waitFor({ timeout: T.nav });
  }

  /// Type into one of this surface's fields; the page-holding half of
  /// the gesture lives here so a spec never needs the raw page.
  async type(field: Locator, text: string): Promise<void> {
    await typeInto(this.ctx.page, field, text);
  }

  /// Wheel a control of this surface to where a click lands on it, over
  /// the pane (or another scroller) that owns it.
  async intoView(target: Locator, over?: Locator): Promise<void> {
    await wheelIntoReach(this.ctx.page, target, { over });
  }

  /// Press-and-hold a row, which is how the workbench's multi-select
  /// starts on touch and on canvas.
  async hold(target: Locator): Promise<void> {
    await longPressOn(this.ctx.page, target);
  }

  // --- the release workbench, served at /metadata/<al-...> ---------------

  workbench(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.metadataWorkbench));
  }

  /// The album entity form - the workbench's own pane for the release.
  albumEditor(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.albumEditor));
  }

  /// Cold-load the workbench on one release and wait for its list.
  async openWorkbench(albumPid: string): Promise<void> {
    await this.ctx.page.goto(`/metadata/${albumPid}`);
    await this.workbench().waitFor({ timeout: T.nav });
    await this.ctx.page
      .locator(sem(SemanticsIds.workbenchList))
      .waitFor({ timeout: T.fetch });
  }

  albumRow(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.workbenchAlbumRow));
  }

  trackRow(pid: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.workbenchRow(pid)));
  }

  /// The editor pane beside the list; holds the album form, one
  /// member's editor, or the bulk form depending on the selection.
  pane(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.workbenchPane));
  }

  selectToggle(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.workbenchSelectToggle));
  }

  bulkPane(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.workbenchBulkPane));
  }

  bulkField(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.workbenchBulkField(name)));
  }

  bulkSave(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.workbenchBulkSave));
  }

  rewriteField(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.albumRewriteField(name)));
  }

  rewriteApply(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.albumRewriteApply));
  }

  rewriteConfirm(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.albumRewriteConfirm));
  }
}
