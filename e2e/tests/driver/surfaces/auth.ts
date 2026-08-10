// The door, and the chrome every screen hangs off.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Api } from '../api';
import { T } from '../budgets';
import { clickThrough, openMenu, typeInto } from '../gestures';
import { Surface } from '../context';

/// Signing in and out.
///
/// Almost nothing calls this. The suite plants the session as a cookie
/// before the first navigation (see tests/fixtures.ts), so a spec opens
/// the app already signed in - which is both faster and one less shared
/// journey for every test to re-drive. What is left here is for the
/// specs whose subject IS the door: first run, sign-up, identity, the
/// accessibility walk, and the walking skeleton.
export class Auth extends Surface {
  /// Drive the real login form, as a person does: open the app cold and
  /// sign in from wherever it puts you.
  async signInViaForm(who: { username: string; password: string } = this.ctx.account) {
    await this.ctx.page.goto('/');
    await this.signInHere(who);
  }

  /// Sign in on the form that is already showing.
  ///
  /// For a spec that arrived at the door by a route of its own - a deep
  /// link the redirect carried through, a sign-out - where opening the
  /// app afresh would throw away the very location under test.
  /// `lands` is what should follow; the chrome, unless the point is that
  /// the login carried somebody somewhere in particular.
  async signInHere(
    who: { username: string; password: string } = this.ctx.account,
    lands?: Locator,
  ) {
    const page = this.ctx.page;
    const username = page.locator(sem(SemanticsIds.loginUsername));
    await username.waitFor({ timeout: T.nav });
    await typeInto(page, username, who.username);
    await typeInto(page, page.locator(sem(SemanticsIds.loginPassword)), who.password);
    await page.locator(sem(SemanticsIds.loginSubmit)).click();
    await (lands ?? page.locator(sem(SemanticsIds.navRegion))).waitFor({ timeout: T.nav });
  }

  /// Walk in off the login screen with an invite.
  ///
  /// Settles on the login form rather than on the chrome: an invited
  /// signup activates the account immediately, so the screen pops back
  /// to the form prefilled. (`signup-result` renders only for the
  /// pending path, where an administrator has still to approve.)
  async signUpViaForm(who: { username: string; password: string; invite: string }) {
    const page = this.ctx.page;
    const field = (id: string) => page.locator(sem(id));
    await clickThrough(field(SemanticsIds.signupOpen), field(SemanticsIds.signupUsername));
    await typeInto(page, field(SemanticsIds.signupUsername), who.username);
    await typeInto(page, field(SemanticsIds.signupPassword), who.password);
    await typeInto(page, field(SemanticsIds.signupInviteToken), who.invite);
    await clickThrough(field(SemanticsIds.signupSubmit), field(SemanticsIds.loginUsername));
  }

  /// The first-run wizard: name the administrator a server has none of
  /// yet. Lands signed in, so what it settles on is the chrome.
  async completeSetup(who: { username: string; password: string }) {
    const page = this.ctx.page;
    await page.goto('/');
    const username = page.locator(sem(SemanticsIds.setupUsername));
    await username.waitFor({ timeout: T.nav });
    await typeInto(page, username, who.username);
    await typeInto(page, page.locator(sem(SemanticsIds.setupPassword)), who.password);
    await typeInto(page, page.locator(sem(SemanticsIds.setupConfirm)), who.password);
    await page.locator(sem(SemanticsIds.setupSubmit)).click();
    await page.locator(sem(SemanticsIds.navRegion)).waitFor({ timeout: T.nav });
  }

  /// The server as the BROWSER sees it.
  ///
  /// An API hand over the page's own request context, so the
  /// `waxdeck_session` cookie is what authenticates and no bearer token
  /// rides along. That distinction is the whole subject of the specs
  /// that drive the door: a spec's own hand answers for the token it was
  /// handed and says nothing about what the app is actually signed in
  /// as - which for a single-sign-on account is not this test's account
  /// at all.
  browserApi(): Api {
    return new Api(this.ctx.page.request, '');
  }

  /// What the server says about the session the browser is holding.
  async session() {
    return this.browserApi().get('/auth/session');
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

  async expectAtLogin() {
    await this.submit().waitFor({ timeout: T.nav });
  }

  /// Open the app cold and stop at the door. For the specs that mean the
  /// door itself, where what the address bar reads on arrival is part of
  /// what they assert.
  async enterLogin() {
    await this.ctx.page.goto('/');
    await this.expectAtLogin();
  }
}

/// The shell itself: the chrome every screen hangs off.
export class Shell extends Surface {
  /// The nav rail, present exactly when the app is signed in and no
  /// pushed screen is over it.
  region(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.navRegion));
  }

  destination(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.navDestination(name)));
  }

  /// A disclosure group in the sidebar. Offered only to an account that
  /// has something in it, which is itself an assertion.
  navGroup(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.navGroup(name)));
  }

  /// The avatar that opens the account menu. Returned as well as
  /// clickable because where it sits is itself an assertion: below rail
  /// width it belongs to the top app bar rather than to the tab bar, and
  /// the only way to tell those apart is geometry.
  account(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.navAccount));
  }

  /// A verb the account menu offers. Signing out is the only one today;
  /// the destinations the menu also carries below rail width keep their
  /// own destination identifiers and come from `destination`.
  accountVerb(name: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.navAccountAction(name)));
  }

  /// Opened, not clicked through: a menu closes under a retried trigger
  /// click, which is what `clickThrough` does while it waits.
  async openAccountMenu(): Promise<void> {
    await openMenu(this.account(), this.accountVerb('signOut'));
  }

  /// An action on the snack bar the app has just shown - an undo, a
  /// "show all". Snack actions publish no identifier, so the label is
  /// what finds them and the spec is what names it.
  snackAction(name: string): Locator {
    return this.ctx.page.getByRole('button', { name });
  }

  /// The bell in the top app bar.
  notificationsBell(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.notificationsBell));
  }

  /// One row of the open bell, newest first.
  notificationRow(index: number): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.notificationRow(index)));
  }

  notificationsClear(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.notificationsClear));
  }

  /// Waits until the bell has something unseen. A row does not arrive
  /// with the change that caused it: the socket says the stream moved,
  /// then the client walks it.
  async notificationsBadged(): Promise<void> {
    await expect(this.notificationsBell()).toHaveAccessibleName(/unread/, {
      timeout: T.fetch,
    });
  }

  /// Opens the bell and waits for its first row, for the same reason
  /// the account menu is opened rather than clicked through.
  async openNotifications(): Promise<void> {
    await openMenu(this.notificationsBell(), this.notificationRow(0));
  }
}

