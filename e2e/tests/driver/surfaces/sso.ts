// Single sign-on, including the identity provider's own form.
//
// The provider is not our app. It publishes no semantics identifiers,
// because it stands in for whatever a deployment actually runs, and its
// login form is plain HTML. Those selectors belong here for exactly the
// reason every other locator does: a spec should say "sign in with
// testidp as gandalf", and this should be the only place that knows the
// form has a field called `idp_username`.

import { Locator } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';

export class Sso extends Surface {
  /// The provider's button on WaxDeck's own login screen.
  provider(id: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.oidcLogin(id)));
  }

  /// Sign in through a provider, from WaxDeck's login screen to the
  /// chrome on the other side.
  ///
  /// Three hops: our button, the provider's form, and the callback the
  /// server turns into a session. Waiting on the URL between them is
  /// what tells a provider that never answered from one that answered
  /// with a refusal.
  async signIn(
    provider: string,
    who: { username: string; password: string },
    at: RegExp,
  ): Promise<void> {
    const page = this.ctx.page;
    const button = this.provider(provider);
    await button.waitFor({ timeout: T.nav });
    await button.click();

    // The provider's own login form, on the provider's own origin.
    await page.waitForURL(at, { timeout: T.nav });
    await page.locator('input[name="idp_username"]').fill(who.username);
    await page.locator('input[name="idp_password"]').fill(who.password);
    await page.locator('button[type="submit"]').click();

    // Back through the server callback, and the app loads signed in.
    await page.locator(sem(SemanticsIds.navRegion)).waitFor({ timeout: T.nav });
  }
}
