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
) {
  if ('shows' in goal) {
    if (!(await goal.shows.isVisible())) {
      await trigger.click({ timeout: 2_000, force: true }).catch(() => {});
    }
    await goal.shows.waitFor({ timeout: T.step });
  } else {
    if (await goal.gone.first().isVisible()) {
      await trigger.click({ timeout: 2_000, force: true }).catch(() => {});
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
export async function wheelIntoView(
  page: Page,
  target: Locator,
  options: { over?: Locator; by?: number } = {},
) {
  const { over, by = 600 } = options;
  const view = page.viewportSize();
  const width = view?.width ?? (await page.evaluate(() => window.innerWidth));
  const height = view?.height ?? (await page.evaluate(() => window.innerHeight));
  const box = over === undefined ? null : await over.boundingBox();
  await page.mouse.move(
    box === null ? width / 2 : box.x + box.width / 2,
    box === null ? height / 2 : Math.min(box.y + box.height / 2, height - 2),
  );
  await expect(async () => {
    await page.mouse.wheel(0, by);
    await expect(target).toBeVisible({ timeout: 1_000 });
  }).toPass({ timeout: T.nav });
}

// Wheel a canvas surface until `target`'s rect is inside the viewport.
//
// `wheelIntoView` answers "does it exist yet"; this answers "can a click
// land on it". A semantics node below the fold still reports visible
// with a real box, and Playwright's own scroll moves the overlay while
// the canvas stays put - which is how choosing a crossfade value opened
// the rewind row's menu instead.
export async function wheelIntoViewport(
  page: Page,
  target: Locator,
  options: { over?: Locator } = {},
) {
  const { over } = options;
  const view = page.viewportSize();
  const width = view?.width ?? (await page.evaluate(() => window.innerWidth));
  const height = view?.height ?? (await page.evaluate(() => window.innerHeight));
  const inside = (box: { y: number; height: number } | null) =>
    box !== null && box.y >= 0 && box.y + box.height <= height;
  await target.waitFor({ timeout: T.nav });
  if (inside(await target.boundingBox())) return;
  const anchor = over === undefined ? null : await over.boundingBox();
  await page.mouse.move(
    anchor === null ? width / 2 : anchor.x + anchor.width / 2,
    anchor === null ? height / 2 : Math.min(anchor.y + anchor.height / 2, height - 2),
  );
  await expect(async () => {
    const box = await target.boundingBox();
    expect(box, 'the target reports a box to scroll toward').toBeTruthy();
    if (!inside(box)) {
      // Short of the gap, so a row just past the fold cannot oscillate.
      await page.mouse.wheel(0, box!.y < 0 ? -120 : 120);
    }
    expect(inside(await target.boundingBox()), 'the target is inside the viewport').toBe(true);
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

// Above the action tier because a menu may be re-opened from scratch
// several times over, each round paying the open again. One gesture's
// quirk rather than a kind of wait, so it is not in `T`.
const MENU_UNIT = 45_000;

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
) {
  await expect(async () => {
    if (settled && (await settled.isVisible())) return;
    await clickToward(trigger, { shows: item });
    // The menu is repositioned as it grows near a screen edge, while a
    // forced click dispatches at the rect a frame earlier - which is how
    // choosing "Off" once stored the row beneath it. Two matching reads
    // are the menu at rest; reduced motion shortens that window without
    // closing it.
    await expect(async () => {
      const before = await item.boundingBox();
      await new Promise((resolve) => setTimeout(resolve, 120));
      const after = await item.boundingBox();
      expect(before).toBeTruthy();
      expect(after).toEqual(before);
    }).toPass({ timeout: 4_000 });
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
export async function openMenu(trigger: Locator, shows: Locator) {
  await expect(async () => {
    await clickToward(trigger, { shows });
  }).toPass({ timeout: T.nav });
}
