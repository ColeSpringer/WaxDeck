// The four ways this suite touches a Flutter canvas.
//
// Everything the specs know about clicking, typing and menus lives here.
// Each primitive is one retried unit around a refusal that arrives
// looking like something else, and the comments are the diagnosis that
// produced it - they were bought one incident at a time and are the
// reason nobody re-solves these.
//
// This is also the only place `force: true` is allowed. A forced click
// skips Playwright's actionability wait, which over canvas is not a
// safety net but a guaranteed timeout: semantics nodes over a live seek
// bar never satisfy the stability heuristics. So the wait is replaced
// rather than dropped - each forced click here sits behind either a
// destination check or a rect-at-rest check, and a spec that wants to
// force one of its own has nowhere to write it.

import { expect, Locator, Page } from '@playwright/test';
import { T } from './budgets';

// Type into a flutter text field and verify the app took the text.
//
// Clicking focuses the DOM input, but flutter binds its editing session
// asynchronously and keys typed in the gap land in the element with
// nothing listening - so the element can hold the whole string over an
// empty controller, and a value check alone reports a field that is
// about to fail its own validator. Flutter rewrites the element from its
// controller when it does bind, which is what makes the second read
// below the app's answer rather than the DOM's.
export async function typeInto(page: Page, field: Locator, text: string) {
  // Bounded: an absent field must fail here with a page snapshot, not
  // silently consume the whole test budget.
  await field.waitFor({ timeout: T.nav });
  await expect(async () => {
    // Re-located and re-clicked every attempt: a lost editing session is
    // re-established by the click, and the handle is never held across a
    // round in which flutter may have rebuilt the node.
    const inner = field.locator('input, textarea');
    const input = (await inner.count()) > 0 ? inner.first() : field;
    await input.click();
    await expect(input).toBeFocused({ timeout: T.step });
    await page.keyboard.press('ControlOrMeta+a');
    await page.keyboard.type(text);
    await expect(input).toHaveValue(text, { timeout: 1_000 });
    // Two matching reads a beat apart, like the menu-at-rest check
    // below: a value flutter never received is gone by the second one.
    await new Promise((resolve) => setTimeout(resolve, 400));
    expect(await input.inputValue()).toBe(text);
    // T.action, not more: a sign-in form fills two fields, and two of
    // these budgets plus their waits have to leave room inside the 120s
    // a spec gets, or a missing field dies on the test timeout with no
    // snapshot.
  }).toPass({ timeout: T.action });
}

// Click a canvas-rendered control and wait for what it opens, as one
// retried unit: flutter web can swallow a click while its handlers are
// still attaching (the click cousin of the keystroke gap typeInto
// retries around), and a swallowed navigation click means the next
// screen never appears at all.
export async function clickThrough(trigger: Locator, appears: Locator) {
  await expect(async () => {
    // A prior attempt's click may have landed with the destination
    // just slow, and navigating away removes the trigger; so the click
    // is skipped once the destination shows and is best-effort
    // otherwise (a swallowed click retries, a vanished trigger means
    // the navigation is already underway).
    if (!(await appears.isVisible())) {
      // Forced, like the a11y suite's canvas clicks: semantics nodes
      // over an animating canvas (a live seek bar) never satisfy the
      // stability heuristics, so an actionability wait just times out.
      await trigger.click({ timeout: 2_000, force: true }).catch(() => {});
    }
    await appears.waitFor({ timeout: T.step });
  }).toPass({ timeout: T.nav });
}

// Click a control the driver cannot reach on its own, as one retried
// unit.
//
// Two shapes of the same refusal. A routed screen animates in from
// below, so its nodes resolve while their rects are still off the bottom
// of the window; and a row inside a flutter list sits wherever the list
// left it, because playwright scrolls DOM containers and a canvas list
// moves for a wheel over it and nothing else. Either way the click is
// refused as outside the viewport with the node resolved and the scroll
// reported done, which reads like anything but a rect that has not
// arrived.
//
// `surface` is the list to wheel, for a row below the fold; omit it for
// a control that is only still arriving. `settled` is what proves the
// click took, and - as in `chooseFromMenu` - it is checked before
// anything else, so a click that landed and then lost its own wait is
// never fired a second time. Pass it for anything that is not idempotent
// and give it something only this click can produce.
export async function clickInView(
  page: Page,
  target: Locator,
  options: { surface?: Locator; settled?: Locator } = {},
) {
  const { surface, settled } = options;
  const view = page.viewportSize();
  // The config sets a viewport, so this is the fallback for a run that
  // does not rather than a live path.
  const height =
    view?.height ?? (await page.evaluate(() => window.innerHeight));
  const inside = (box: { y: number; height: number } | null) =>
    box !== null && box.y >= 0 && box.y + box.height <= height;
  await expect(async () => {
    if (settled !== undefined && (await settled.isVisible())) return;
    // A missing box fails the attempt rather than picking a scroll
    // direction from nothing: the node churn this exists for is exactly
    // when boundingBox comes back null.
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
    // No click timeout of its own: one expiring after the press was
    // dispatched is what would let a retry fire the control twice.
    await target.click({ force: true });
    if (settled !== undefined) await settled.waitFor({ timeout: T.step });
  }).toPass({ timeout: T.action });
}

// A menu may have to be re-opened from scratch several times over, so
// its whole-unit budget sits above the action tier rather than on it:
// a barrier click closes the menu the previous attempt opened, and each
// round then pays the open again. Named here rather than folded into
// `T` because it is one gesture's quirk, not a kind of wait.
const MENU_UNIT = 45_000;

// Open a menu and choose a row from it, as one retried unit.
//
// `clickThrough` is wrong for a menu and this is the difference: it
// re-clicks its trigger whenever the destination is not showing, and on
// a retry that click lands on the modal barrier and closes the menu the
// previous attempt opened. So the trigger is clicked only when the row
// is not already visible, and the whole open-and-choose repeats from a
// closed menu when a click is swallowed.
//
// `settled` is what proves the choice took: a sheet the row opens, or -
// by default - the menu going away, which is what a value picker does.
// It is also checked before anything else, for the choice that took and
// then outran its own wait: the menu is gone by the next attempt, so
// every one after it re-opens the menu over the surface the choice
// already reached and none of them ever look at what they were waiting
// for - a helper that fails its whole budget after having succeeded.
// That check is why `settled` has to be something only the chosen row
// can produce: one already on screen when this is called reads as a
// choice that already happened, and the menu is never opened at all.
export async function chooseFromMenu(
  trigger: Locator,
  item: Locator,
  settled?: Locator,
) {
  await expect(async () => {
    if (settled && (await settled.isVisible())) return;
    if (!(await item.isVisible())) {
      await trigger.click({ timeout: 2_000, force: true }).catch(() => {});
      await item.waitFor({ timeout: T.step });
    }
    // The menu animates into place - and near a screen edge it is
    // repositioned as it grows - while a forced click dispatches at
    // whatever rect the semantics overlay held a frame earlier. That
    // one-frame disagreement is how choosing "Off" from a menu at the
    // bottom of the screen landed on the row beneath it and silently
    // stored the wrong value. Two matching reads a beat apart is the
    // menu at rest; until then the click would be a coin toss.
    //
    // Reduced motion shortens that window rather than closing it: the
    // engine scales animations to 5% of their duration, it does not
    // make a frame's worth of disagreement impossible, and motion-smoke
    // runs this same code with animations full length.
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
