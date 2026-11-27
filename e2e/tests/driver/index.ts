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

import { Locator, Page, Route, WebSocketRoute, expect } from '@playwright/test';
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

  /// The page this app drives, for the waits Playwright hangs off a
  /// page rather than a locator - arming a `waitForResponse` before the
  /// navigation that causes it. The `page` fixture is the same object
  /// for the default app; a second device has no other way to reach it.
  get page(): Page {
    return this.ctx.page;
  }

  /// The same account on a second page - another device in the
  /// household, which is what the connect and sync scenarios are about.
  /// A second ACCOUNT is a second `createApp` with its own mint.
  on(page: Page): App {
    return new App({ ...this.ctx, page });
  }

  /// This page's network, in the test's hand. Asked before the page opens
  /// a socket (its first navigation), so every socket it opens goes
  /// through a route the handle holds: `off()` then fails the page's
  /// requests and refuses its upgrades (a CDP session on the page alone,
  /// because the context's `setOffline` takes the other tab of a two-tab
  /// scenario down too) and drops the sockets it holds, which network
  /// emulation leaves open; `on()` puts it back, and the page hears that
  /// it is online again as it does on a real network. `sockets` says, per
  /// socket in the order they were opened, when the server took it (the
  /// page's first frame, which it sends once it is open), if it did.
  /// `holdNext(path)` holds the first request to an API path the page
  /// sends once it is back on, until released.
  async network(): Promise<PageNetwork> {
    const page = this.page;
    const open = new Set<WebSocketRoute>();
    const sockets: { acceptedAt?: number }[] = [];
    let online = true;
    // A routed socket is still the browser's own, opened by the page, so
    // the cookie and the emulated network apply to it as to any other.
    await page.routeWebSocket(
      () => true,
      (ws) => {
        const socket: { acceptedAt?: number } = {};
        sockets.push(socket);
        open.add(ws);
        const server = ws.connectToServer();
        // The page speaks first (its subscribe frame) only once the server
        // has taken the upgrade.
        ws.onMessage((message) => {
          socket.acceptedAt ??= Date.now();
          server.send(message);
        });
      },
    );
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('Network.enable');
    const link = { latency: 0, downloadThroughput: -1, uploadThroughput: -1 };
    return {
      sockets,
      off: async () => {
        online = false;
        await cdp.send('Network.emulateNetworkConditions', { offline: true, ...link });
        for (const ws of open) await ws.close({ code: 1001, reason: 'offline' }).catch(() => {});
        open.clear();
      },
      on: async () => {
        online = true;
        await cdp.send('Network.emulateNetworkConditions', { offline: false, ...link });
        // That hands `navigator.onLine` back to the browser's own reading,
        // which stays offline where the browser has no network but loopback
        // (a sandbox), so the page would never hear `online`. Set online
        // here, it fires wherever the page last read offline. All-default
        // values clear the state instead of setting it.
        await cdp.send('Network.overrideNetworkState', {
          offline: false,
          latency: 1,
          downloadThroughput: 1e9,
          uploadThroughput: 1e9,
          connectionType: 'ethernet',
        });
      },
      holdNext: async (path: string) => {
        let release = () => {};
        const released = new Promise<void>((resolve) => (release = resolve));
        const held: HeldRequest = {
          release: async () => release(),
        };
        // What goes while the page is off fails as it would have; the
        // first once it is on waits, and every later one goes.
        await page.route(`**/api/v1${path}`, async (route: Route) => {
          if (!online || held.sentAt !== undefined) return route.continue();
          held.sentAt = Date.now();
          await released;
          await route.continue();
        });
        return held;
      },
    };
  }
}

/// The API path a request URL names (`/auth/session`), or undefined for
/// anything that is not an API request.
export function apiPath(url: string): string | undefined {
  const path = new URL(url).pathname;
  return path.startsWith('/api/v1/') ? path.slice('/api/v1'.length) : undefined;
}

/// A request `PageNetwork.holdNext` holds: when the page sent it, once it
/// has, and the hand that lets it go.
export interface HeldRequest {
  sentAt?: number;
  release(): Promise<void>;
}

/// A page's network in a test's hand; see `App.network`.
export interface PageNetwork {
  readonly sockets: readonly { readonly acceptedAt?: number }[];
  off(): Promise<void>;
  on(): Promise<void>;
  holdNext(path: string): Promise<HeldRequest>;
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
  clickOnceForAnswer,
  pressOnce,
  clickUntilRequested,
  chooseFromMenu,
  typeInto,
  wheelIntoReach,
  wheelIntoView,
} from './gestures';
export { DEST } from './nav';
export type { Ctx } from './context';
export type { Dest, Destination } from './nav';
