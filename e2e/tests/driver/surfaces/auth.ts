// The door, and the chrome every screen hangs off.

import { expect, Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Api } from '../api';
import { T } from '../budgets';
import { clickThrough, openMenu, typeInto } from '../gestures';
import { Surface } from '../context';

/// Signing in and out.
///
/// Almost nothing calls this: the suite plants the session as a cookie
/// before the first navigation (tests/fixtures.ts), so a spec opens the
/// app already signed in. What is left is for the specs whose subject IS
/// the door - first run, sign-up, identity, the accessibility walk.
export class Auth extends Surface {
  /// Drive the real login form, as a person does: open the app cold and
  /// sign in from wherever it puts you.
  async signInViaForm(who: { username: string; password: string } = this.ctx.account) {
    await this.ctx.page.goto('/');
    await this.signInHere(who);
  }

  /// Sign in on the form that is already showing, for a spec that
  /// arrived by a route of its own and would lose the location under
  /// test by opening the app afresh. `lands` is what should follow.
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

  /// Walk in off the login screen with an invite. Settles on the form
  /// rather than the chrome: an invited signup activates immediately and
  /// pops back to it prefilled, `signup-result` being the pending path.
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

  /// The server as the BROWSER sees it: the page's own request context,
  /// so the `waxdeck_session` cookie authenticates and no bearer token
  /// rides along. A spec's own hand answers for the token it was handed
  /// and says nothing about what the app is signed in as.
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

  /// Open the app cold and stop at the door, for the specs where what
  /// the address bar reads on arrival is part of the assertion.
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

  /// The avatar that opens the account menu. Returned rather than
  /// clicked because where it sits is itself an assertion: below rail
  /// width it belongs to the app bar, and only geometry tells them apart.
  account(): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.navAccount));
  }

  /// A verb the account menu offers. The destinations it also carries
  /// below rail width keep their own ids and come from `destination`.
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

  /// A row of the open bell by its copy, a menu row having no text of
  /// its own. Not by position: the catalog is one installation every
  /// worker writes to, so newest-first is not mine-first.
  notificationNamed(name: string): Locator {
    return this.ctx.page.getByRole('menuitem', { name, exact: true });
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

  /// Open the bell and wait for one particular piece of news.
  ///
  /// Re-opened rather than waited out: the menu holds the rows it opened
  /// with, and the badge that brought us here was not necessarily this
  /// test's news.
  async openNotificationsUntil(name: string): Promise<Locator> {
    const row = this.notificationNamed(name);
    await expect(async () => {
      if (await row.isVisible()) return;
      // Closed first, because `openMenu` reads an open menu as done.
      await this.ctx.page.keyboard.press('Escape');
      await expect(this.notificationRow(0)).toBeHidden({ timeout: T.step });
      await openMenu(this.notificationsBell(), this.notificationRow(0));
      await expect(row).toBeVisible({ timeout: T.step });
      // The assert tier, not the fetch one: waiting for the news to
      // arrive is `notificationsBadged`'s job, so a budget long enough
      // for that would turn a copy change into a minute of nothing.
    }).toPass({ timeout: T.assert });
    return row;
  }
}

