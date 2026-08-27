// The player, and the deck bar it expands from.

import { Locator, expect } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { chooseFromMenu, clickThrough, clickToward, typeInto } from '../gestures';

export class Player extends Surface {
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

  /// Wait until the player is up and holding something, expanding it
  /// from the deck bar when playback started docked.
  ///
  /// Play lands in the dock and the full player is a choice, so a spec
  /// that needs the player makes that choice here. `clickToward` fires
  /// the expand click only while the toggle is missing - once the
  /// player is up it overlays the shell and the deck bar leaves the
  /// semantics tree - and `pushOnce` behind the affordance makes an
  /// accidental double-click safe.
  ///
  /// Call it with local playback started. The expand identifier is
  /// shared by every face of the bar, and a bar showing a remote
  /// session or a restore offer expands to a different screen - so on
  /// those faces this navigates somewhere else and then times out.
  async ready(): Promise<void> {
    const expand = this.ctx.page.locator(sem(SemanticsIds.deckExpand));
    await expect(async () => {
      await clickToward(expand, { shows: this.toggle() });
    }).toPass({ timeout: T.nav });
  }

  /// Stop the clock, and settle when the transport agrees it has.
  /// Expands the full player on the way when playback is docked - the
  /// toggle it drives is the player's - so the player is up when this
  /// returns.
  ///
  /// A method rather than a click in a spec, because the forced click
  /// belongs to the driver - and because "paused" is the button's own
  /// accessible name here (it announces the action, so a paused player
  /// offers Play), not something appearing or disappearing that
  /// `clickToward` could wait on.
  ///
  /// Read, click and assert are one retried unit, for two reasons that
  /// both bite. Flutter web swallows a click while its handlers are
  /// still attaching, which is why every other gesture here retries;
  /// and the name is only trustworthy once something is playing, so a
  /// single read against a player that has not started yet says "Play"
  /// and would leave this returning with the clock still running - the
  /// flake it exists to remove. Waiting for /Pause/ first is what makes
  /// the guard mean "already paused" rather than "not started".
  async pause(): Promise<void> {
    await this.ready();
    await expect(this.toggle()).toHaveAccessibleName(/Pause/i, {
      timeout: T.nav,
    });
    await expect(async () => {
      if (/Play/i.test((await this.toggle().getAttribute('aria-label')) ?? '')) {
        return;
      }
      await this.toggle().click({ force: true });
      await expect(this.toggle()).toHaveAccessibleName(/Play/i, {
        timeout: T.step,
      });
    }).toPass({ timeout: T.nav });
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

  /// The keyboard's way out, which the player registers as a scoped
  /// command for as long as it is the current route.
  async dismissWithEscape(settledOn: Locator): Promise<void> {
    await expect(async () => {
      if (!(await settledOn.isVisible())) {
        await this.ctx.page.keyboard.press('Escape');
      }
      await settledOn.waitFor({ timeout: T.step });
    }).toPass({ timeout: T.nav });
  }

  /// A click on the backdrop beside the content, which is how a pointer
  /// dismisses a modal surface and the only way down a mouse has that
  /// does not involve aiming at a 40 px chevron.
  ///
  /// By coordinate, and the one gesture here that has to be: the
  /// dismissing region publishes no semantics node on purpose. A
  /// tappable node the size of the window would sit over every named
  /// control on the player and a screen reader would meet it first, so
  /// there is deliberately nothing to address by identifier.
  ///
  /// Answers false where the region does not exist, rather than clicking
  /// somewhere useless and timing out with nothing to say. Two ways it
  /// can be absent: the content column is 520 px, so a narrow window is
  /// all content; and the scaffold switches to a side-by-side
  /// arrangement on a short landscape window, where the content runs
  /// edge to edge behind a 24 px gutter and a fixed click at x=24 lands
  /// on the island's own left edge (Rect.contains includes it).
  async dismissByBackdrop(settledOn: Locator): Promise<boolean> {
    const page = this.ctx.page;
    const viewport = page.viewportSize();
    if (viewport === null) return false;
    const gutter = (viewport.width - 520) / 2;
    if (gutter < 90 || viewport.height < 480) return false;
    // A quarter into the gutter: clear of the content box on one side
    // and of the window edge on the other, at any width that got here.
    const x = Math.round(gutter / 2);
    await expect(async () => {
      if (!(await settledOn.isVisible())) {
        await page.mouse.click(x, Math.round(viewport.height / 2));
      }
      await settledOn.waitFor({ timeout: T.step });
    }).toPass({ timeout: T.nav });
    return true;
  }
}
