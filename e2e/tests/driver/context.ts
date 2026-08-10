// What every surface needs to do its job.

import { Locator, Page } from '@playwright/test';
import { Account } from '../accounts';
import { sem } from '../semantics-ids';
import { Api } from './api';

/// What every surface needs: a page to drive, an API hand for the
/// server side, and whose account this is.
export interface Ctx {
  readonly page: Page;
  readonly api: Api;
  readonly account: Account;
}

/// The shape every driver surface shares: it holds its ctx, and it can
/// find prose.
///
/// `text` is here because it was defined nine times and had already
/// diverged: seven copies returned `.first()`, two took an exact flag
/// and returned the unfiltered locator, so the same call meant "first
/// match" on most surfaces and a strict-mode violation on two. One
/// definition, one meaning: prose carries no semantics identifier -
/// the spec supplies the words - and the first match is the answer,
/// because "this text is on screen" is what a spec ever asks of prose.
/// A spec that needs a count still has one: `toHaveCount(0)` on the
/// first match holds exactly when there are no matches at all.
export abstract class Surface {
  constructor(protected readonly ctx: Ctx) {}

  text(value: string | RegExp, options: { exact?: boolean } = {}): Locator {
    return this.ctx.page
      .getByText(value, { exact: options.exact ?? false })
      .first();
  }

  /// A control on this surface that carries its own generated
  /// identifier; the spec passes the SemanticsIds constant.
  control(id: string): Locator {
    return this.ctx.page.locator(sem(id));
  }
}

