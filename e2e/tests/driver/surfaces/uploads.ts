// Uploads: the add sheet, the grouping dialog, and the uploads screen.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { clickThrough } from '../gestures';

export class Uploads extends Surface {
  /// The shell's add control, which an account with no upload right is
  /// never offered.
  add(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.homeAdd));
  }

  /// The file row inside the add sheet.
  fromFile(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.addUploadFile));
  }

  /// The quota header the uploads screen draws.
  quota(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.uploadQuota));
  }

  /// The dialog that asks what the picked files are.
  mediaConfirm(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.uploadMediaConfirm));
  }

  /// The per-submission identification switch on that same dialog.
  identify(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.uploadIdentify));
  }

  /// Confirm one picked file with identification turned off, so the
  /// entry it opens is never searched.
  async confirmWithoutIdentifying(): Promise<void> {
    await this.identify().waitFor({ timeout: T.nav });
    await this.identify().click({ force: true });
    await this.mediaConfirm().click({ force: true });
  }

  /// Pick files through the real chooser.
  ///
  /// The chooser event is armed before the click that opens it: a native
  /// dialog is not a page element and there is no second chance to catch
  /// it once it has opened.
  async pickFiles(files: readonly string[]): Promise<void> {
    const page = this.ctx.page;
    await clickThrough(this.add(), this.fromFile());
    // Armed and awaited together. The click can throw on the node churn
    // every gesture here retries around, and a `waitForEvent` left with
    // nobody attached rejects half a minute later with no handler -
    // which support/hangprobe.ts records as taking the runner down
    // rather than failing the test.
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      this.fromFile().click({ force: true }),
    ]);
    await chooser.setFiles([...files]);
  }

  /// Declare what several picked files are to each other. Only asked
  /// when there is more than one.
  async groupAs(kind: string): Promise<void> {
    const page = this.ctx.page;
    await page.locator(sem(SemanticsIds.uploadGrouping)).waitFor({ timeout: T.nav });
    await page.locator(sem(SemanticsIds.uploadGroupingOption(kind))).click({ force: true });
    await this.mediaConfirm().click({ force: true });
  }

  /// Confirm a single file, where the dialog asks only the media type.
  async confirmMedia(): Promise<void> {
    await this.mediaConfirm().click({ force: true });
  }

  /// Drop a real file onto the canvas.
  ///
  /// Through CDP, so the browser builds the drag store from the host
  /// path and the web plugin's entry traversal sees a genuine file entry
  /// - a synthetic DataTransfer hands it null. Dispatched as a retried
  /// unit, like clickThrough: the canvas can swallow a drop while the
  /// engine is mid-frame, and a missed drop leaves no state behind, so
  /// dropping again is safe.
  async dropFile(file: string): Promise<void> {
    const page = this.ctx.page;
    const client = await page.context().newCDPSession(page);
    const size = page.viewportSize();
    expect(size, 'the run declares a viewport to drop into').toBeTruthy();
    const x = size!.width / 2;
    const y = size!.height / 2;
    const data = { items: [], files: [file], dragOperationsMask: 1 };
    const dialog = this.mediaConfirm();
    await expect(async () => {
      if (!(await dialog.isVisible())) {
        await client.send('Input.dispatchDragEvent', { type: 'dragEnter', x, y, data });
        await client.send('Input.dispatchDragEvent', { type: 'dragOver', x, y, data });
        await client.send('Input.dispatchDragEvent', { type: 'drop', x, y, data });
      }
      await dialog.waitFor({ timeout: T.step });
    }).toPass({ timeout: T.fetch });
  }
}
