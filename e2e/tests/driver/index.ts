// The app, as something a spec can talk to.
//
// A spec says what it wants to happen; this layer knows how. That
// division is the whole point: 292 raw `page.locator(...)` calls used to
// mean that renaming a control, moving a screen or restructuring the
// sidebar edited a dozen spec files, none of which were about the thing
// that changed. Now the locators live in one place per surface, and a
// spec reads as the scenario it is.
//
// The `page` fixture a spec receives is narrowed to a type with no
// `locator` and no `getBy*` on it, so this is not a convention anybody
// has to remember - reaching around the driver does not compile.
//
// **Copy stays with the spec.** The driver finds a control and hands
// back a locator; whether it says the right thing is the spec's
// assertion, because that copy is the contract with the listener and a
// spec is where a contract belongs. The driver uses text of its own only
// where a control carries no identifier, and says so where it does.

import { Locator, Page, expect } from '@playwright/test';
import { Account } from '../accounts';
import { SemanticsIds, sem } from '../semantics-ids';
import { Api } from './api';
import { T } from './budgets';
import { Nav } from './nav';
import { Seed } from './seed';
import { Ctx } from './context';
import { Auth, Shell } from './surfaces/auth';
import { Music } from './surfaces/music';
import { Player } from './surfaces/player';
import { Podcasts } from './surfaces/podcasts';
import { Search } from './surfaces/search';
import { Settings } from './surfaces/settings';

/// One account driving one page.
export class App {
  readonly nav: Nav;
  readonly seed: Seed;
  readonly auth: Auth;
  readonly shell: Shell;
  readonly music: Music;
  readonly search: Search;
  readonly player: Player;
  readonly podcasts: Podcasts;
  readonly settings: Settings;

  constructor(readonly ctx: Ctx) {
    this.nav = new Nav(ctx.page);
    this.seed = new Seed(ctx.api);
    this.auth = new Auth(ctx);
    this.shell = new Shell(ctx);
    this.music = new Music(ctx);
    this.search = new Search(ctx);
    this.player = new Player(ctx);
    this.podcasts = new Podcasts(ctx);
    this.settings = new Settings(ctx);
  }

  get api(): Api {
    return this.ctx.api;
  }

  get account(): Account {
    return this.ctx.account;
  }

  /// The same account on a second page - another device in the
  /// household, which is what the connect and sync scenarios are about.
  /// A second ACCOUNT is a second `createApp` with its own mint.
  on(page: Page): App {
    return new App({ ...this.ctx, page });
  }
}

export function createApp(ctx: Ctx): App {
  return new App(ctx);
}

/// The rule the shared server imposes on assertions, stated once here
/// because it is the one thing a spec author has to hold in mind.
///
/// Per-user state - a queue, a star, a position, a subscription, a
/// preference - belongs to this test's own account, so exact counts and
/// absence are both legal. Catalog state does not: a reused stack
/// carries previous runs' uploads, and three other workers are writing
/// to it right now, so a catalog listing is asserted by the presence of
/// what this test made and never by what it does not contain.
///
/// Deliberately prose rather than helpers. A pair of `own`/`catalog`
/// assertion functions lived here and had no callers; the first draft of
/// one sorted with the default lexicographic comparator, which is wrong
/// for the numbers its signature invited. Untested helpers teach the
/// rule less well than the rule does, and the first spec that needs one
/// can write it against a real case.

/// Retry around the file-mutation lease.
///
/// One installation, four workers: a delete, an upload, a rescan and an
/// unfetch all take the same catalog lease, and a spec that wants it
/// while a sibling holds it is refused with `catalog-busy`. That refusal
/// clears on its own and is nothing to do with the code under test - any
/// other refusal is, and is rethrown with the server's own message.
/// The budget is the fetch tier, not the assert tier: what is being
/// waited on is another worker's upload, rescan or delete finishing,
/// which is server-side work off the request and exactly what that tier
/// names. It costs nothing on the failure path either - a refusal that
/// is not `catalog-busy` is rethrown on the first attempt rather than
/// waiting the budget out.
export async function retryCatalogBusy<T>(
  attempt: () => Promise<T>,
  options: { what?: string; within?: number } = {},
): Promise<T> {
  const { what = 'the catalog lease should free', within = T.fetch } = options;
  let result: T;
  await expect
    .poll(
      async () => {
        try {
          result = await attempt();
          return true;
        } catch (e) {
          if (String(e).includes('catalog-busy')) return false;
          throw e;
        }
      },
      { timeout: within, message: what },
    )
    .toBe(true);
  return result!;
}

export { T, J } from './budgets';
export { clickInView, clickThrough, chooseFromMenu, typeInto } from './gestures';
export { DEST } from './nav';
export type { Ctx } from './context';
export type { Dest, Destination } from './nav';
