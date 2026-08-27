// The app, as something a spec can talk to. A spec says what it wants
// to happen; this layer knows how, so a renamed control edits one
// surface rather than a dozen spec files.
//
// The `page` fixture a spec receives has no `locator` and no `getBy*`,
// so reaching around the driver does not compile.
//
// **Copy stays with the spec**, because it is the contract with the
// listener. The driver uses text of its own only where a control
// carries no identifier, and says so where it does.

import { Locator, Page, expect } from '@playwright/test';
import { Account } from '../accounts';
import { SemanticsIds, sem } from '../semantics-ids';
import { Api } from './api';
import { T } from './budgets';
import { Nav } from './nav';
import { Seed } from './seed';
import { Ctx } from './context';
import { Auth, Shell } from './surfaces/auth';
import { Admin } from './surfaces/admin';
import { Artwork } from './surfaces/artwork';
import { Books } from './surfaces/books';
import { Cast } from './surfaces/cast';
import { Discovery } from './surfaces/discovery';
import { Home } from './surfaces/home';
import { Metadata } from './surfaces/metadata';
import { Music } from './surfaces/music';
import { Player } from './surfaces/player';
import { Playlists } from './surfaces/playlists';
import { Podcasts } from './surfaces/podcasts';
import { Queue } from './surfaces/queue';
import { Radio } from './surfaces/radio';
import { Review } from './surfaces/review';
import { Search } from './surfaces/search';
import { Settings } from './surfaces/settings';
import { Sso } from './surfaces/sso';
import { Stats } from './surfaces/stats';
import { Uploads } from './surfaces/uploads';
import { Sharing } from './surfaces/sharing';

/// One account driving one page.
export class App {
  readonly nav: Nav;
  readonly seed: Seed;
  readonly auth: Auth;
  readonly shell: Shell;
  readonly admin: Admin;
  readonly artwork: Artwork;
  readonly books: Books;
  readonly cast: Cast;
  readonly home: Home;
  readonly discovery: Discovery;
  readonly metadata: Metadata;
  readonly music: Music;
  readonly search: Search;
  readonly player: Player;
  readonly queue: Queue;
  readonly radio: Radio;
  readonly playlists: Playlists;
  readonly podcasts: Podcasts;
  readonly review: Review;
  readonly settings: Settings;
  readonly sharing: Sharing;
  readonly sso: Sso;
  readonly stats: Stats;
  readonly uploads: Uploads;

  constructor(readonly ctx: Ctx) {
    this.nav = new Nav(ctx.page);
    this.seed = new Seed(ctx.api);
    this.auth = new Auth(ctx);
    this.shell = new Shell(ctx);
    this.admin = new Admin(ctx);
    this.artwork = new Artwork(ctx);
    this.books = new Books(ctx);
    this.cast = new Cast(ctx);
    this.home = new Home(ctx);
    this.discovery = new Discovery(ctx);
    this.metadata = new Metadata(ctx);
    this.music = new Music(ctx);
    this.search = new Search(ctx);
    this.player = new Player(ctx);
    this.queue = new Queue(ctx);
    this.radio = new Radio(ctx);
    this.playlists = new Playlists(ctx);
    this.podcasts = new Podcasts(ctx);
    this.review = new Review(ctx);
    this.settings = new Settings(ctx);
    this.sharing = new Sharing(ctx);
    this.sso = new Sso(ctx);
    this.stats = new Stats(ctx);
    this.uploads = new Uploads(ctx);
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

/// The rule the shared server imposes on assertions.
///
/// Per-user state - a queue, a star, a position, a preference - belongs
/// to this test's own account, so exact counts and absence are both
/// legal. Catalog state does not: a reused stack carries earlier runs'
/// uploads and three workers are writing to it, so a catalog listing is
/// asserted by the presence of what this test made, never by absence.
///
/// Prose rather than helpers, deliberately: an untested pair of them
/// lived here with no callers and a wrong comparator.

export { retryCatalogBusy } from './retry';

export { T, J } from './budgets';
export {
  clickInView,
  clickThrough,
  clickUntil,
  clickUntilRequested,
  chooseFromMenu,
  typeInto,
  wheelIntoReach,
  wheelIntoView,
} from './gestures';
export { DEST } from './nav';
export type { Ctx } from './context';
export type { Dest, Destination } from './nav';
