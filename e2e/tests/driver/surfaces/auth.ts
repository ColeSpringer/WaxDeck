// The door, and the chrome every screen hangs off.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { T } from '../budgets';
import { clickThrough, typeInto } from '../gestures';
import { Ctx } from '../context';

/// Signing in and out.
///
/// Almost nothing calls this. The suite plants the session as a cookie
/// before the first navigation (see tests/fixtures.ts), so a spec opens
/// the app already signed in - which is both faster and one less shared
/// journey for every test to re-drive. What is left here is for the
/// specs whose subject IS the door: first run, sign-up, identity, the
/// accessibility walk, and the walking skeleton.
export class Auth {
  constructor(private readonly ctx: Ctx) {}

  /// Drive the real login form, as a person does.
  async signInViaForm(who: { username: string; password: string } = this.ctx.account) {
    const page = this.ctx.page;
    await page.goto('/');
    const username = page.locator(sem(SemanticsIds.loginUsername));
    await username.waitFor({ timeout: T.nav });
    await typeInto(page, username, who.username);
    await typeInto(page, page.locator(sem(SemanticsIds.loginPassword)), who.password);
    await page.locator(sem(SemanticsIds.loginSubmit)).click();
    await page.locator(sem(SemanticsIds.navRegion)).waitFor({ timeout: T.nav });
  }

  /// The login screen's field, for a spec asserting what it says.
  field(which: 'username' | 'password'): Locator {
    return this.ctx.page.locator(
      sem(which === 'username' ? SemanticsIds.loginUsername : SemanticsIds.loginPassword),
    );
  }

  submit(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.loginSubmit));
  }

  /// What the form says when it refuses. Returned, not asserted: the
  /// wording is the spec's to judge.
  error(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.loginError));
  }

  async expectAtLogin() {
    await this.submit().waitFor({ timeout: T.nav });
  }

  /// Sign out through the app. The router's redirect is what unwinds the
  /// stack, so there is nothing to pop by hand.
  async signOut() {
    await this.ctx.page.locator(sem(SemanticsIds.logoutButton)).click();
    await this.expectAtLogin();
  }
}

/// The shell itself: the chrome every screen hangs off.
export class Shell {
  constructor(private readonly ctx: Ctx) {}

  /// The nav rail, present exactly when the app is signed in and no
  /// pushed screen is over it.
  region(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.navRegion));
  }

  destination(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.navDestination(name)));
  }

  /// Waits until the app has booted far enough to draw the chrome. What
  /// a signed-in spec is waiting for when it opens the app at all.
  async ready() {
    await this.region().waitFor({ timeout: T.nav });
  }

  async openAccountMenu(): Promise<void> {
    await clickThrough(
      this.ctx.page.locator(sem(SemanticsIds.navAccount)),
      this.ctx.page.locator(sem(SemanticsIds.navAccountAction('settings'))),
    );
  }

  accountAction(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.navAccountAction(name)));
  }
}

