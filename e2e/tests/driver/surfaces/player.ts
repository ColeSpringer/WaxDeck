// The player, and the deck bar it expands from.

import { Locator, expect } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import {
  chooseFromMenu,
  clickThrough,
  clickToward,
  rectAtRest,
  typeInto,
} from '../gestures';

/// What a control is called right now. Flutter publishes a button's
/// label as its text rather than as `aria-label`, so reading only the
/// attribute answers null and a guard built on it never fires.
async function nameOf(control: Locator): Promise<string> {
  return (await control.getAttribute('aria-label')) ?? (await control.textContent()) ?? '';
}

/// The beat between a rest's two reads: longer than the frames from one
/// track ending to the next taking its place, which read Play under the
/// old track's name. A gesture's quirk like `rectAtRest`'s, not a tier.
const TRACK_CHANGE_BEAT = 400;

export class Player extends Surface {
  /// Play/pause. Also the marker that something is playing at all,
  /// which is why so many navigation steps settle on it.
  toggle(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerToggle));
  }

  /// The deck bar's own play/pause, for playback that stays docked.
  deckToggle(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.deckPlay));
  }

  /// The deck bar's skip to the next entry.
  deckNext(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.deckNext));
  }

  /// The launch offer's Resume, standing in the deck bar's slot when a
  /// launch found a queue to put back.
  offerResume(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.deckOfferResume));
  }

  /// The Retry on the shell's toast after a start failed - the one a
  /// listener at the deck bar has, since the pane is the full player's.
  startRetry(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerStartRetry));
  }

  /// The sleep timer's control, whose name says what is armed.
  sleepTimer(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.sleepTimerOpen));
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

  /// The hero, while it has more than one picture to turn through.
  artwork(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerArtwork));
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
  async pause(): Promise<void> {
    await this.ready();
    await this.pauseWith(this.toggle());
  }

  /// [pause] from the deck bar, leaving playback docked rather than
  /// expanding the player over the shell - whose chrome, the toasts and
  /// the bar's own controls, a docked spec goes on to use.
  async pauseDocked(): Promise<void> {
    await this.pauseWith(this.deckToggle());
  }

  /// Read, press and assert as one retried unit, for two reasons that
  /// both bite. Flutter web swallows a click while its handlers are still
  /// attaching, which is why every other gesture here retries; and the
  /// name is the play intent, which a player that has not been asked to
  /// play yet reads as "Play", so a single read there would leave this
  /// returning with the clock about to run. Waiting for /Pause/ first is
  /// what makes the guard mean "already paused" rather than "not
  /// started". The intent reads Pause from the moment a load means to
  /// play, so a press then lands that start paused where it began: a spec
  /// that wants the clock to have run first waits for it.
  ///
  /// And Play alone proves nothing: a press swallowed while the queue
  /// moves on would pass for a landed one wherever the next track rests
  /// on Play. A press counts once the transport rests on the track it was
  /// made on ([restsOn]), and the latch that stops a retry pressing again
  /// holds that track, raised only once the press was dispatched.
  private async pauseWith(toggle: Locator): Promise<void> {
    await expect(toggle).toHaveAccessibleName(/Pause/i, { timeout: T.nav });
    let pressedOn: string | undefined;
    await expect(async () => {
      if (pressedOn !== undefined && (await this.restsOn(toggle, pressedOn))) return;
      // Only a control offering Pause is pressed: between tracks it reads
      // Play, and a press then asks the next one to play.
      await expect(toggle).toHaveAccessibleName(/Pause/i, { timeout: T.step });
      const track = await this.nowPlaying();
      await toggle.click({ force: true });
      pressedOn = track;
      await expect
        .poll(() => this.restsOn(toggle, track), {
          timeout: T.step,
          message: 'the transport should rest on the track it was paused on',
        })
        .toBe(true);
    }).toPass({ timeout: T.nav });
  }

  /// Whether the transport rests on [track]: the control offers Play and
  /// the browser's media session still names that track. A track change
  /// names the next one from the start of its load, so it never passes;
  /// but between the old track ending and the next taking its place the
  /// session still names the old one, which is why this reads twice, a
  /// beat apart.
  private async restsOn(toggle: Locator, track: string): Promise<boolean> {
    const rests = async () =>
      /Play/i.test(await nameOf(toggle)) && (await this.nowPlaying()) === track;
    if (!(await rests())) return false;
    await new Promise((resolve) => setTimeout(resolve, TRACK_CHANGE_BEAT));
    return rests();
  }

  /// What the browser's media session names as playing; empty when it
  /// names nothing.
  private nowPlaying(): Promise<string> {
    return this.ctx.page.evaluate(() => navigator.mediaSession?.metadata?.title ?? '');
  }

  /// Start the clock again from the full player, and settle when the
  /// transport agrees it has: [pause] the other way round, with the
  /// same retried unit and for the same reasons.
  ///
  /// The name is the play intent, not proof of sound: a stream that is
  /// waiting for data reads Pause too, which is the state a spec about
  /// what happens next wants to start from.
  async play(): Promise<void> {
    await this.ready();
    await expect(async () => {
      if (/Pause/i.test(await nameOf(this.toggle()))) return;
      await this.toggle().click({ force: true });
      await expect(this.toggle()).toHaveAccessibleName(/Pause/i, {
        timeout: T.step,
      });
    }).toPass({ timeout: T.nav });
  }

  /// Accept the launch offer. Settles on the deck bar's transport, which
  /// the offer stands in place of until it is taken.
  async acceptOffer(): Promise<void> {
    await clickThrough(this.offerResume(), this.deckToggle());
  }

  /// Arm the sleep timer to stop where the current chapter ends, opening
  /// its sheet on the way; the end-of-chapter row is a book's alone. What
  /// got armed is in the timer control's name, which is the spec's to
  /// read. Restored per attempt for the reason [setSpeed] is: the control
  /// sits on the player's dismissing scaffold.
  async armEndOfChapter(): Promise<void> {
    await chooseFromMenu(
      this.sleepTimer(),
      this.ctx.page.locator(sem(SemanticsIds.sleepTimerChapter)),
      { restore: () => this.reopen() },
    );
  }

  /// The full player's seek bar: a slider whose value is the position
  /// spelled out against the length.
  seekBar(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.playerSeek));
  }

  /// Press the seek bar at `fraction` of its length, the way a pointer
  /// scrubs it: the press previews and the release commits. By
  /// coordinate, because a position along a slider has no node of its own.
  ///
  /// Pressed again only while `landed` says no press took: over canvas a
  /// press can be swallowed, and one that did land must not land twice,
  /// since on a stream the server cuts a seek is a new encode. The caller
  /// says what proves it landed, which for a cut is the mint it asks for.
  async seekTo(fraction: number, landed: () => boolean): Promise<void> {
    const page = this.ctx.page;
    const bar = this.seekBar();
    await expect(async () => {
      if (!landed()) {
        await rectAtRest(bar);
        const box = await bar.boundingBox();
        expect(box, 'the seek bar reports a box').toBeTruthy();
        await page.mouse.click(box!.x + box!.width * fraction, box!.y + box!.height / 2);
      }
      await expect
        .poll(landed, { timeout: T.step, message: 'the seek should land' })
        .toBe(true);
    }).toPass({ timeout: T.nav });
  }

  /// One press on a chapter row, which seeks the book to that chapter's
  /// head and leaves play or pause as it was. One attempt, at rest: the
  /// caller's own loop proves it landed, by the checkpoint the seek
  /// writes.
  async tapChapter(index: number): Promise<void> {
    const row = this.chapter(index);
    await rectAtRest(row);
    await row.click({ force: true });
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
  ///
  /// Restored per attempt as belt and braces: the scaffold holds a
  /// dismissal back while its islands move, but a press that still
  /// misses collapses the player and takes the chip with it.
  ///
  /// Inherits [reopen]'s precondition, and through it [ready]'s: this
  /// drives the player of local playback, not a bar holding somebody
  /// else's session.
  async setSpeed(percent: number): Promise<void> {
    await chooseFromMenu(
      this.speed(),
      this.ctx.page.locator(sem(SemanticsIds.playerSpeedPreset(percent))),
      { restore: () => this.reopen() },
    );
  }

  /// Puts the player back if a press dismissed it: only then is the deck bar
  /// up (a menu's barrier hides it too). One bounded click, as this runs in
  /// `chooseFromMenu`'s loop; [ready]'s precondition applies.
  private async reopen(): Promise<void> {
    const expand = this.ctx.page.locator(sem(SemanticsIds.deckExpand));
    if (!(await expand.isVisible())) return;
    await clickToward(expand, { shows: this.toggle() });
  }

  /// Open the player's overflow and choose "add to playlist".
  ///
  /// Behind the overflow because that is where every verb acting on the
  /// item lives since the header was rebuilt onto the scaffold: it has
  /// two controls, and this is the second one's menu. Settles on the
  /// sheet's own "new list" row, which only the sheet draws.
  ///
  /// Restored per attempt for the reason [setSpeed] is - the overflow
  /// sits on the same dismissing scaffold the rate chip does, and a
  /// press that misses it leaves the same way - and inherits the same
  /// precondition.
  async addToPlaylist(): Promise<void> {
    const page = this.ctx.page;
    await chooseFromMenu(
      page.locator(sem(SemanticsIds.playerMore)),
      page.locator(sem(SemanticsIds.addToPlaylist)),
      {
        settled: page.locator(sem(SemanticsIds.addToPlaylistNew)),
        restore: () => this.reopen(),
      },
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
