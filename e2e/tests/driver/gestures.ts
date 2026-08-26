// The ways this suite touches a Flutter canvas. Each primitive is one
// retried unit around a refusal that arrives looking like something
// else.
//
// Also the only place `force: true` is allowed: over canvas an
// actionability wait is a guaranteed timeout rather than a safety net,
// so each forced click here sits behind a destination or rect-at-rest
// check instead.

import { expect, Locator, Page } from '@playwright/test';
import { T } from './budgets';

// Type into a flutter text field and verify the app took the text.
//
// Flutter binds its editing session asynchronously, so keys typed in the
// gap leave the DOM holding a string the controller never got. It
// rewrites the element from the controller once bound, which is what the
// second read below is asking.
export async function typeInto(page: Page, field: Locator, text: string) {
  // Bounded, so an absent field fails here with a page snapshot.
  await field.waitFor({ timeout: T.nav });
  await expect(async () => {
    // Re-located and re-clicked each attempt: the click re-establishes a
    // lost editing session, and flutter may have rebuilt the node.
    const inner = field.locator('input, textarea');
    const input = (await inner.count()) > 0 ? inner.first() : field;
    await input.click();
    await expect(input).toBeFocused({ timeout: T.step });
    await page.keyboard.press('ControlOrMeta+a');
    await page.keyboard.type(text);
    await expect(input).toHaveValue(text, { timeout: 1_000 });
    // A value flutter never received is gone by the second read.
    await new Promise((resolve) => setTimeout(resolve, 400));
    expect(await input.inputValue()).toBe(text);
    // T.action, not more: two of these have to fit a spec's 120s.
  }).toPass({ timeout: T.action });
}

// Submit a flutter text field and wait for what Enter opens, as one
// retried unit.
//
// The shell's search field navigates on submit and not on focus - a
// caret landing in it used to carry a visitor off whatever they were
// reading - so clicking it is not a way in. Empty submits are legal and
// are how the screen is reached with nothing typed.
export async function submitThrough(
  page: Page,
  field: Locator,
  appears: Locator,
) {
  await field.waitFor({ timeout: T.nav });
  await expect(async () => {
    if (await appears.isVisible()) return;
    // The DOM input flutter parents under the node, when there is one:
    // keys go to whatever holds the editing session.
    const inner = field.locator('input, textarea');
    const input = (await inner.count()) > 0 ? inner.first() : field;
    await input.click();
    // Focus first, and let the attempt fail here if the click was
    // swallowed. A page-level Enter goes to whatever holds focus, which
    // in the smoke walk is the nav row clicked a moment ago - so a
    // refused click would navigate somewhere else and every retry after
    // it would run from the wrong screen. typeInto asserts the same
    // thing for the same reason.
    await expect(input).toBeFocused({ timeout: T.step });
    await page.keyboard.press('Enter');
    await appears.waitFor({ timeout: T.step });
  }).toPass({ timeout: T.nav });
}

/// Which button a gesture presses. The default is the primary one; a
/// surface that raises its menu from a secondary tap - a card, a listing
/// row - says so, and the option rides down to every gesture built on
/// [clickToward]. Getting this wrong is not a missed menu but a
/// different verb: a primary tap on a card plays it.
export interface Press {
  readonly button?: 'left' | 'right';
}

// The retried-click attempt everything below shares: unless the goal is
// already met, fire a bounded forced click and hold to the goal.
//
// Both polarities guard on the goal not being met yet, because a prior
// click may have landed with the transition merely slow, and firing
// again double-triggers the control. `gone` waits for a count of zero:
// a flutter node that is gone is detached, and it may match many rows.
export async function clickToward(
  trigger: Locator,
  goal: { shows: Locator } | { gone: Locator },
  press: Press = {},
) {
  const { button = 'left' } = press;
  if ('shows' in goal) {
    if (!(await goal.shows.isVisible())) {
      await trigger.click({ timeout: 2_000, force: true, button }).catch(() => {});
    }
    await goal.shows.waitFor({ timeout: T.step });
  } else {
    if (await goal.gone.first().isVisible()) {
      await trigger.click({ timeout: 2_000, force: true, button }).catch(() => {});
    }
    await expect(goal.gone).toHaveCount(0, { timeout: T.step });
  }
}

// Click a canvas control and wait for what it opens, as one retried
// unit: flutter web can swallow a click while its handlers are still
// attaching, and a swallowed navigation click never arrives at all.
export async function clickThrough(trigger: Locator, appears: Locator) {
  await expect(async () => {
    await clickToward(trigger, { shows: appears });
  }).toPass({ timeout: T.nav });
}

// Click a control the driver cannot reach on its own, as one retried
// unit.
//
// Two shapes of one refusal: a routed screen's nodes resolve while their
// rects are still off-screen, and a canvas list moves for a wheel and
// nothing else. Either way the click is refused as outside the viewport
// with the node resolved and the scroll reported done.
//
// `surface` is the list to wheel; `settled` proves the click took, and
// is checked first so a landed one is never fired twice. Give it
// something only this click can produce.
export async function clickInView(
  page: Page,
  target: Locator,
  options: { surface?: Locator; settled?: Locator } = {},
) {
  const { surface, settled } = options;
  const view = page.viewportSize();
  const height =
    view?.height ?? (await page.evaluate(() => window.innerHeight));
  const inside = (box: { y: number; height: number } | null) =>
    box !== null && box.y >= 0 && box.y + box.height <= height;
  await expect(async () => {
    if (settled !== undefined && (await settled.isVisible())) return;
    // A missing box fails the attempt rather than picking a direction
    // from nothing; the churn this exists for is when it comes back null.
    let box = await target.boundingBox();
    expect(box, 'the control reports a box').toBeTruthy();
    if (surface !== undefined && !inside(box)) {
      const over = await surface.boundingBox();
      expect(over, 'the surface reports a box to scroll').toBeTruthy();
      await page.mouse.move(
        over!.x + over!.width / 2,
        Math.min(over!.y + over!.height / 2, height - 2),
      );
      await page.mouse.wheel(0, box!.y < 0 ? -120 : 120);
      box = await target.boundingBox();
    }
    expect(inside(box), 'the control is in view').toBe(true);
    // No timeout of its own: one expiring after the press was dispatched
    // would let a retry fire the control twice.
    await target.click({ force: true });
    if (settled !== undefined) await settled.waitFor({ timeout: T.step });
  }).toPass({ timeout: T.action });
}

// Bring something below the fold into existence.
//
// A flutter list is slivers: a row that is not laid out publishes no
// semantics node at all, so there is nothing to scroll to and only a
// wheel over the canvas moves the list. `over` places the cursor for a
// scroll view that is not the one under the middle of the window.
// Parks the cursor where a wheel should land: over the given scroller's
// centre clamped into the window - a pane partly off-screen otherwise
// parks it outside, where every wheel is a silent no-op - or the
// window's middle.
async function aimWheel(
  page: Page,
  over: Locator | undefined,
  width: number,
  height: number,
) {
  const box = over === undefined ? null : await over.boundingBox();
  const clamp = (v: number, edge: number) => Math.min(Math.max(v, 2), edge - 2);
  await page.mouse.move(
    box === null ? width / 2 : clamp(box.x + box.width / 2, width),
    box === null ? height / 2 : clamp(box.y + box.height / 2, height),
  );
}

export async function wheelIntoView(
  page: Page,
  target: Locator,
  options: { over?: Locator; by?: number } = {},
) {
  const { over, by = 600 } = options;
  const view = page.viewportSize();
  const width = view?.width ?? (await page.evaluate(() => window.innerWidth));
  const height = view?.height ?? (await page.evaluate(() => window.innerHeight));
  await aimWheel(page, over, width, height);
  await expect(async () => {
    await page.mouse.wheel(0, by);
    await expect(target).toBeVisible({ timeout: 1_000 });
  }).toPass({ timeout: T.nav });
}

// Wheel a canvas surface until a click aimed at `target` lands on it:
// the rect at rest, fully inside the window, and its centre inside the
// window's middle half - or the best position its scroll can offer.
//
// `wheelIntoView` answers "does it exist yet"; this answers "can a
// click land on it". Two refusals hide behind a node that looks fine.
// A node below the fold still reports a box, and Playwright's own
// scroll moves the semantics overlay while the canvas stays put -
// which is how choosing a crossfade value opened the rewind row's menu
// instead; fully-inside is what keeps that scroll a no-op at click
// time. And flutter clips a part-scrolled node's rect to what it
// paints, so a shelf card sliding under the app bar keeps publishing a
// box - a shorter one, pinned to the clip edge - which passes every
// inside-the-window test while a click at its centre stops reaching
// the card. Measured on the continue shelf: a right click at the
// reported centre raises the card's menu at 264, 236 and 176 px of
// reported height, and raises nothing at 116. In CI that click landed
// on the first Never played card two shelves down and opened its menu
// instead.
//
// The middle half rather than an inset: the band is wider than the
// wheel notch, so a rect just outside it cannot be stepped over and
// back forever. When a wheel moves nothing - confirmed through a rest,
// so a scroll frame landing late does not read as a spent scroll - the
// band is let go and fully-inside is enough. That cannot re-admit the
// clipped rect: the wheel fires toward the middle, which is the
// direction that uncovers a scroll-clipped target, so a wheel that
// moves nothing means the scroll holds nothing over it on that side.
// Horizontal reach is checked but not driven - no caller aims past a
// row's own width - so a sideways-clipped target fails loudly instead
// of taking a click that would miss it.
export async function wheelIntoReach(
  page: Page,
  target: Locator,
  options: { over?: Locator } = {},
) {
  const { over } = options;
  const view = page.viewportSize();
  const width = view?.width ?? (await page.evaluate(() => window.innerWidth));
  const height = view?.height ?? (await page.evaluate(() => window.innerHeight));
  type Box = { x: number; y: number; width: number; height: number };
  const middleOf = (box: Box) => box.y + box.height / 2;
  const inBand = (box: Box) =>
    middleOf(box) >= height / 4 && middleOf(box) <= (height * 3) / 4;
  const inWindow = (box: Box) =>
    box.x >= 0 &&
    box.x + box.width <= width &&
    box.y >= 0 &&
    box.y + box.height <= height;
  await target.waitFor({ timeout: T.nav });
  // The box the last wheel was fired from, kept across attempts: a
  // fresh read matching it means that wheel moved nothing.
  let spent: Box | null = null;
  let aimed = false;
  await expect(async () => {
    const seen = await target.boundingBox();
    expect(seen, 'the target reports a box to scroll toward').toBeTruthy();
    const same = (box: Box) =>
      spent !== null &&
      box.x === spent.x &&
      box.y === spent.y &&
      box.width === spent.width &&
      box.height === spent.height;
    let box = seen!;
    if ((inBand(box) && inWindow(box)) || same(box)) {
      // At rest before the rect is handed to a click: content arriving
      // above the target moves it after this gesture returns, and a
      // stall read mid-glide is a scroll that has not landed yet, not
      // one that is spent.
      await rectAtRest(target);
      const rested = await target.boundingBox();
      expect(rested, 'the target still reports a box at rest').toBeTruthy();
      box = rested!;
      if (inBand(box) && inWindow(box)) return;
      if (same(box)) {
        expect(
          inWindow(box),
          'the target is as reachable as its scroll allows',
        ).toBe(true);
        return;
      }
      // The rest surfaced late movement; wheel again from where it is.
    }
    if (!aimed) {
      aimed = true;
      await aimWheel(page, over, width, height);
    }
    spent = box;
    await page.mouse.wheel(0, middleOf(box) < height / 2 ? -120 : 120);
    const moved = await target.boundingBox();
    expect(
      moved !== null && inBand(moved) && inWindow(moved),
      'the target is where a click reaches it',
    ).toBe(true);
  }).toPass({ timeout: T.action });
}

// Press and hold, which is how a canvas list starts a multi-select.
//
// Coordinates and a real delay, not a synthesized event: flutter reads a
// long press off the pointer staying down past its own 500 ms, which a
// click helper releases far too soon for.
export async function longPressOn(page: Page, target: Locator, holdMs = 900) {
  const box = await target.boundingBox();
  expect(box, 'the row to press is on screen').toBeTruthy();
  await page.mouse.move(box!.x + box!.width / 2, box!.y + box!.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(holdMs);
  await page.mouse.up();
}

// Drag one row of a canvas list onto another.
//
// Coordinates rather than a drop target: a reorderable list publishes no
// DOM element to drop onto. The travel is stepped because a single jump
// reads as a teleport and the recognizer never starts.
export async function dragOnto(page: Page, handle: Locator, onto: Locator) {
  const from = await handle.boundingBox();
  const to = await onto.boundingBox();
  expect(from && to, 'both drag handles are on screen').toBeTruthy();
  await page.mouse.move(from!.x + from!.width / 2, from!.y + from!.height / 2);
  await page.mouse.down();
  await page.mouse.move(to!.x + to!.width / 2, to!.y + to!.height / 2, { steps: 12 });
  await page.mouse.up();
}

// Two matching reads, 120 ms apart, are a rect at rest. A forced click
// dispatches at a rect read a frame earlier, so a surface that moves
// its controls while they stand - a menu repositioned as it grows, a
// wizard card rebuilt as the scan behind it advances - gets the press
// wherever the control used to be. Reduced motion shortens the moving
// window without closing it.
export async function rectAtRest(target: Locator) {
  await expect(async () => {
    const before = await target.boundingBox();
    await new Promise((resolve) => setTimeout(resolve, 120));
    const after = await target.boundingBox();
    expect(before).toBeTruthy();
    expect(after).toEqual(before);
  }).toPass({ timeout: 4_000 });
}

// Above the action tier because a menu may be re-opened from scratch
// several times over, each round paying the open again. One gesture's
// quirk rather than a kind of wait, so it is not in `T`; exported for
// the surfaces that build the same open-and-pick shape around their own
// trigger.
export const MENU_UNIT = 45_000;

// Open a menu and choose a row from it, as one retried unit.
//
// Not `clickThrough`: that re-clicks its trigger whenever the
// destination is missing, and on a retry the click lands on the modal
// barrier and closes the menu the last attempt opened.
//
// `settled` proves the choice took - a sheet the row opens, or by
// default the menu going away. Checked first, for the choice that
// landed and then outran its own wait, which is why it must be
// something only the chosen row can produce.
export async function chooseFromMenu(
  trigger: Locator,
  item: Locator,
  settled?: Locator,
  press: Press = {},
) {
  await expect(async () => {
    if (settled && (await settled.isVisible())) return;
    await clickToward(trigger, { shows: item }, press);
    // At rest before the pick: near a screen edge the menu is
    // repositioned as it grows, which is how choosing "Off" once stored
    // the row beneath it.
    await rectAtRest(item);
    await item.click({ force: true });
    if (settled) {
      await settled.waitFor({ timeout: T.step });
    } else {
      await expect(item).toBeHidden({ timeout: T.step });
    }
  }).toPass({ timeout: MENU_UNIT });
}

// Open a menu and leave it standing, for the callers that let somebody
// else pick from it. Behaviourally `clickThrough` today; the separate
// name stays because "open the menu" is what the call sites mean, and a
// menu's trigger sits behind the barrier once it opens.
export async function openMenu(
  trigger: Locator,
  shows: Locator,
  press: Press = {},
) {
  await expect(async () => {
    await clickToward(trigger, { shows }, press);
  }).toPass({ timeout: T.nav });
}
