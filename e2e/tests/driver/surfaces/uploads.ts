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

  /// Open the medium chooser on that same dialog, the click and the menu
  /// it opens as one retried unit: the dialog has only just opened.
  async openMediaType(): Promise<void> {
    const chooser = this.ctx.page.locator(sem(SemanticsIds.uploadMediaType));
    await chooser.waitFor({ timeout: T.nav });
    await clickThrough(chooser, this.mediaTypeOption('music'));
  }

  /// One row of the medium chooser, once it is open.
  mediaTypeOption(type: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.uploadMediaTypeOption(type)));
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

  /// Pick files from the uploads screen's own add control, armed the
  /// same way as [pickFiles].
  async pickOnScreen(files: readonly string[]): Promise<void> {
    const page = this.ctx.page;
    const pick = page.locator(sem(SemanticsIds.uploadPick));
    await pick.waitFor({ timeout: T.nav });
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      pick.click({ force: true }),
    ]);
    await chooser.setFiles([...files]);
  }

  /// An upload row's status line, which says what phase it is in.
  phase(uploadId: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.uploadPhase(uploadId)));
  }

  /// Bring an upload row's status line fully inside the window. Rows run
  /// newest first, so sessions other workers open on the shared account
  /// push an older one down, and a refresh can carry it either way past
  /// the window, out of the semantics tree. Lost: wheel to the top, then
  /// down a step per attempt until it is built; built: wheel toward it.
  async revealPhase(uploadId: string): Promise<void> {
    const page = this.ctx.page;
    const phase = this.phase(uploadId);
    const view = page.viewportSize();
    expect(view, 'the run declares a viewport to wheel in').toBeTruthy();
    const height = view!.height;
    await page.mouse.move(view!.width / 2, height / 2);
    let searching = false;
    await expect(async () => {
      if (!(await phase.isVisible())) {
        await page.mouse.wheel(0, searching ? 600 : -1_000_000);
        searching = true;
        expect(await phase.isVisible(), 'the row is built').toBe(true);
      }
      searching = false;
      const box = await phase.boundingBox();
      expect(box, 'the row reports a box').toBeTruthy();
      if (box!.y >= 0 && box!.y + box!.height <= height) return;
      await page.mouse.wheel(0, box!.y < 0 ? -120 : 120);
      expect(false, 'the row is inside the window').toBe(true);
    }).toPass({ timeout: T.nav });
  }

  /// How many Retry controls an upload row draws, read once while its
  /// status line sits inside the window: polled, a row pushed out of the
  /// window meanwhile would read as drawing none.
  async retryCountInView(uploadId: string): Promise<number> {
    const box = await this.phase(uploadId).boundingBox();
    const height = this.ctx.page.viewportSize()?.height ?? 0;
    expect(
      box !== null && box.y >= 0 && box.y + box.height <= height,
      'the row is on screen while its Retry is counted',
    ).toBe(true);
    return this.retry(uploadId).count();
  }

  /// An upload row's Retry, offered only once its transfer gave up.
  retry(uploadId: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.uploadRetry(uploadId)));
  }

  /// The batch ids the account already has. An upload row is kept for a
  /// week and the account outlives the run, so what is this run's is the
  /// batch that was not here before and holds its files.
  async batchIds(): Promise<Set<string | undefined>> {
    return new Set((await this.rows()).map((r) => r.batchId));
  }

  /// Wait for the batch a pick of [files] opened (one not in [before])
  /// to stage every member under one review entry, and answer that
  /// entry's id. Other journeys open batches beside it, so rows are read
  /// back by file name.
  async stagedEntry(
    files: readonly string[],
    before: ReadonlySet<string | undefined>,
  ): Promise<string> {
    let entryId = '';
    await expect(async () => {
      const fresh = (await this.rows()).filter(
        (r) =>
          r.batchId !== undefined &&
          !before.has(r.batchId) &&
          files.includes(r.fileName),
      );
      const batchId = fresh[0]?.batchId;
      expect(batchId, 'the pick should stage under a batch of its own').toBeTruthy();
      const members = fresh.filter((r) => r.batchId === batchId && r.state === 'staged');
      expect(members.map((r) => r.fileName).sort()).toEqual([...files].sort());
      expect(members[0].reviewEntryId, 'finalize linked the entry').toBeTruthy();
      for (const m of members) expect(m.reviewEntryId).toBe(members[0].reviewEntryId);
      entryId = members[0].reviewEntryId!;
    }).toPass({ timeout: T.fetch });
    return entryId;
  }

  private async rows() {
    return (await this.ctx.api.get('/uploads', { query: { limit: 100 } })).uploads ?? [];
  }

  /// Pick a whole folder through the real chooser, armed the same way
  /// as [pickFiles], from the add control with semantics id [addId]
  /// (home's by default). Chromium answers a `webkitdirectory` chooser
  /// with one directory path and hands the page every file beneath it.
  async pickFolder(dir: string, addId?: string): Promise<void> {
    const page = this.ctx.page;
    const add = addId === undefined ? this.add() : page.locator(sem(addId));
    await clickThrough(add, this.fromFolder());
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
