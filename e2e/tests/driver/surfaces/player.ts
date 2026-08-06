// The player, and the deck bar it expands from.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Ctx } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickThrough, typeInto } from '../gestures';

export class Player {
  constructor(private readonly ctx: Ctx) {}

  /// Play/pause. Also the marker that something is playing at all,
  /// which is why so many navigation steps settle on it.
  toggle(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerToggle));
  }

  /// The trim chip, which reports time actually saved once the session
  /// has seeked over lead silence. Positions stay honest, so this is the
  /// only quick proof that trimmed playback is not ordinary playback.
  trim(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerTrim));
  }

  speed(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerSpeed));
  }

  /// The star, which announces its action rather than its state - so
  /// what it is called is how a spec reads the state.
  star(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.starButton('')));
  }

  /// Wait until the player is up and holding something.
  async ready(): Promise<void> {
    await this.toggle().waitFor({ timeout: T.nav });
  }

  /// Choose a playback rate from the speed sheet. One tap to any rate,
  /// where the cycling button this replaced could only walk to it.
  ///
  /// Through `chooseFromMenu` rather than a bare forced click: the sheet
  /// is a trigger that opens a list and dismisses on choosing, which is
  /// a menu in every way that matters here, and what that gesture brings
  /// is the rect-at-rest check. A forced click dispatches at whatever
  /// rect the semantics overlay held a frame earlier, which near a
  /// screen edge lands one row off - the difference between 1.5x and
  /// whatever sits beside it.
  async setSpeed(percent: number): Promise<void> {
    await chooseFromMenu(
      this.speed(),
      this.ctx.page.locator(sem(SemanticsIds.playerSpeedPreset(percent))),
    );
  }

  /// Open the player's overflow and choose "add to playlist".
  ///
  /// Behind the overflow because that is where every verb acting on the
  /// item lives since the header was rebuilt onto the scaffold: it has
  /// two controls, and this is the second one's menu. Settles on the
  /// sheet's own "new list" row, which only the sheet draws.
  async addToPlaylist(): Promise<void> {
    const page = this.ctx.page;
    await chooseFromMenu(
      page.locator(sem(SemanticsIds.playerMore)),
      page.locator(sem(SemanticsIds.addToPlaylist)),
      page.locator(sem(SemanticsIds.addToPlaylistNew)),
    );
  }

  /// The spoken face's progress bar, in whichever unit it is spanning.
  /// The chapter is the default; the whole book is one press away,
  /// because a nine-hour bar moves a pixel a minute and "how far through
  /// the book am I" is the question a chapter view cannot answer.
  timeline(unit: 'chapter' | 'book'): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerTimeline(unit)));
  }

  /// A chapter row, which is the player's own bottom region rather than
  /// a button that opens a sheet.
  chapter(index: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerChapter(index)));
  }

  bookmark(index: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerBookmark(index)));
  }

  /// Drop a mark. The listener's own act, not a side effect of
  /// listening past it. Forced for the same reason every control on this
  /// face is: a row inside a sheet over a live progress bar never
  /// satisfies the stability heuristics.
  async deleteBookmark(index: number): Promise<void> {
    await this.ctx.page
      .locator(sem(SemanticsIds.playerBookmarkDelete(index)))
      .click({ force: true });
  }

  /// Switch the progress bar to span the whole book. Forced: the bar it
  /// sits beside is animating whenever anything is playing, which is
  /// always when this control is on screen.
  async spanWholeBook(): Promise<void> {
    await this.timeline('book').click({ force: true });
  }

  /// Keep a place on purpose, which is a different thing from the resume
  /// position the transport writes on its own.
  async addBookmark(note: string): Promise<void> {
    const page = this.ctx.page;
    await clickThrough(
      page.locator(sem(SemanticsIds.playerBookmarks)),
      page.locator(sem(SemanticsIds.playerBookmarkSheet)),
    );
    await typeInto(page, page.locator(sem(SemanticsIds.playerBookmarkNote)), note);
    await page.locator(sem(SemanticsIds.playerBookmarkAdd)).click({ force: true });
  }

  /// The player's own way out. Not a "Back" button: it is a collapse
  /// chevron since the scaffold rebuild, and a name match walks past the
  /// player onto the screen underneath - which is how a spec came to pop
  /// the wrong screen.
  async collapse(settledOn: Locator): Promise<void> {
    await clickThrough(this.ctx.page.locator(sem(SemanticsIds.playerBack)), settledOn);
  }

  /// A control on the player, by identifier, for the surfaces that have
  /// not earned a method yet.
  control(id: string): Locator {
    return this.ctx.page.locator(sem(id));
  }

  /// Text the player is showing - the elapsed readout, a title, the name
  /// of what a queue is playing from. The clock carries no identifier of
  /// its own (only the spoken faces publish a timeline handle), so this
  /// is the "no id exists" case the copy rule allows; the pattern is the
  /// spec's, which is where the judgement belongs.
  text(what: string | RegExp): Locator {
    return this.ctx.page.getByText(what).first();
  }

  /// Pick a value from a menu the player owns.
  async choose(trigger: Locator, item: Locator, settled?: Locator): Promise<void> {
    await chooseFromMenu(trigger, item, settled);
  }
}
