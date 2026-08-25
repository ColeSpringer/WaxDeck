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

  /// The folder row beside it, which the web build only draws because
  /// the picker port answers `canPickFolders` there.
  fromFolder(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.addUploadFolder));
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

  /// What the identification switch currently reads, or undefined when
  /// the engine exposes no state to read. Flutter web puts the toggled
  /// state on the semantics node's aria-checked (or an input child,
  /// depending on engine version).
  private async identifyState(): Promise<boolean | undefined> {
    const own = await this.identify().getAttribute('aria-checked');
    if (own !== null) return own === 'true';
    const input = this.identify().locator('input').first();
    if ((await input.count()) > 0) return input.isChecked();
    return undefined;
  }

  /// Confirm one picked file with identification turned off, so the
  /// entry it opens is never searched.
  async confirmWithoutIdentifying(): Promise<void> {
    await this.identify().waitFor({ timeout: T.nav });
    if ((await this.identifyState()) === undefined) {
      // No readable state on this engine: the blind toggle it always
      // was.
      await this.identify().click({ force: true });
    } else {
      // Toggled and read back rather than fired blind: under a loaded
      // run the tap can land while the dialog is still settling and
      // leave the switch on, which quietly turns "goes straight in"
      // into a queued entry. The poll retries the assertion, and the
      // click fires only on a read that confirmed the switch is still
      // on - an undefined read (the node re-creating mid-settle) just
      // polls again rather than counting as "already off".
      await expect
        .poll(
          async () => {
            const state = await this.identifyState();
            if (state === true) {
              await this.identify().click({ force: true });
            }
            return state;
          },
          {
            timeout: T.nav,
            message: 'the identification switch should read off',
          },
        )
        .toBe(false);
    }
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

  /// Pick a whole folder through the real chooser, armed the same way
  /// as [pickFiles]. Chromium answers a `webkitdirectory` chooser with
  /// one directory path and hands the page every file beneath it.
  async pickFolder(dir: string): Promise<void> {
    const page = this.ctx.page;
    await clickThrough(this.add(), this.fromFolder());
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      this.fromFolder().click({ force: true }),
    ]);
    await chooser.setFiles(dir);
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
