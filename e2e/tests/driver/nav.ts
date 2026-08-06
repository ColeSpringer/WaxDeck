// Where the app's screens are, and how you know you arrived.
//
// This table is the reason a shell rebuild stops breaking a dozen
// unrelated specs. It used to be that every spec that wanted the
// playlists screen knew the way there - open the Music disclosure, click
// the row - so moving playlists under a section, or renaming a
// destination, edited eleven files. Now the route is written once and a
// spec says where it wants to be.
//
// **Arriving by URL is the default.** `enter(dest)` is a cold load of
// the destination's own path, which the server's SPA fallback answers
// since locations moved into the path. With the session planted as a
// cookie, that costs one app boot - less than a boot plus a login plus
// a walk through the chrome, which is what every spec used to pay. What
// it also does is stop nine specs from asserting the sidebar's structure
// by accident.
//
// `to(dest)` is the walk through the chrome, for the specs where
// navigation itself is the subject, and `driver-smoke.spec.ts` walks
// every entry that way - so the chrome coverage the enter-default takes
// out of the other specs is concentrated in one test whose failure says
// "dest playlists is unreachable" instead of nine specs failing nine
// different ways.

import { expect, Locator, Page } from '@playwright/test';
import { SemanticsIds, sem } from '../semantics-ids';
import { T } from './budgets';
import { clickThrough } from './gestures';

/// A destination: the location a stranger can open, the control that
/// proves the screen is up, and - when the chrome can reach it - the
/// walk that gets there.
///
/// `arrival` must be something ONLY this screen draws. The hazard is
/// real and has bitten: episode rows appear on the podcasts hub's
/// shelves as well as on a show screen, so gating arrival on a row let a
/// navigation step "succeed" without navigating.
export interface Dest {
  readonly path: string;
  readonly arrival: (page: Page) => Locator;
  /// The chrome walk. Absent for a location with no way in from the nav
  /// rail - a pushed screen, or one reached from another screen's own
  /// control.
  readonly walk?: (page: Page) => Promise<void>;
  /// Why the chrome walk needs more than a signed-in account. A row the
  /// sidebar hides until the account has something behind it cannot be
  /// walked to by a test with a fresh account, and driver-smoke says so
  /// out loud rather than quietly covering one destination less.
  readonly walkNeeds?: string;
}

const at = (id: string) => (page: Page) => page.locator(sem(id));

/// Clicks a nav-rail destination and waits for the screen behind it.
const railTo = (destination: string, arrival: (page: Page) => Locator) =>
  async (page: Page) => {
    await clickThrough(
      page.locator(sem(SemanticsIds.navDestination(destination))),
      arrival(page),
    );
  };

/// Uploads, the review queue, tasks and the admin console are the
/// sidebar's curation group, which is a disclosure rather than a row.
/// clickThrough makes opening it idempotent, so a walk that is already
/// there costs nothing.
const openCuration = async (page: Page, reveals: string) => {
  await clickThrough(
    page.locator(sem(SemanticsIds.navGroup('curation'))),
    page.locator(sem(SemanticsIds.navDestination(reveals))),
  );
};

const curationTo = (destination: string, arrival: (page: Page) => Locator) =>
  async (page: Page) => {
    await openCuration(page, destination);
    await clickThrough(
      page.locator(sem(SemanticsIds.navDestination(destination))),
      arrival(page),
    );
  };

/// A section of the admin console, reached the way a person reaches it:
/// the console first, then its own section list.
const adminSection = (name: string, path: string, marker: string): Dest => ({
  path,
  arrival: at(marker),
  walk: async (page: Page) => {
    await openCuration(page, 'admin');
    await clickThrough(
      page.locator(sem(SemanticsIds.navDestination('admin'))),
      page.locator(sem(SemanticsIds.adminSection(name))),
    );
    await clickThrough(
      page.locator(sem(SemanticsIds.adminSection(name))),
      page.locator(sem(marker)),
    );
  },
});

export const DEST = {
  home: {
    path: '/',
    arrival: at(SemanticsIds.homeScreen),
    walk: railTo('home', at(SemanticsIds.homeScreen)),
  },
  search: {
    path: '/search',
    arrival: (page) => page.locator(sem(SemanticsIds.searchFilter('all'))),
    walk: async (page) => {
      // Search is a field in the sidebar header at this width, not a
      // rail destination: clicking it opens the screen and keeps the
      // caret, which is the whole reason it is a field.
      await clickThrough(
        page.locator(sem(SemanticsIds.searchField)),
        page.locator(sem(SemanticsIds.searchFilter('all'))),
      );
    },
  },
  music: {
    path: '/music',
    arrival: (page) => page.locator(sem(SemanticsIds.musicTile('artists'))),
    walk: railTo('music', (page) => page.locator(sem(SemanticsIds.musicTile('artists')))),
  },
  tracks: {
    path: '/music/tracks',
    arrival: at(SemanticsIds.listingShuffle),
    walk: async (page) => {
      await clickThrough(
        page.locator(sem(SemanticsIds.navDestination('music'))),
        page.locator(sem(SemanticsIds.musicTile('tracks'))),
      );
      await clickThrough(
        page.locator(sem(SemanticsIds.musicTile('tracks'))),
        page.locator(sem(SemanticsIds.listingShuffle)),
      );
    },
  },
  artists: {
    path: '/music/artists',
    arrival: at(SemanticsIds.indexSort),
    walk: async (page) => {
      await clickThrough(
        page.locator(sem(SemanticsIds.navDestination('music'))),
        page.locator(sem(SemanticsIds.musicTile('artists'))),
      );
      await clickThrough(
        page.locator(sem(SemanticsIds.musicTile('artists'))),
        page.locator(sem(SemanticsIds.indexSort)),
      );
    },
  },
  playlists: {
    path: '/playlists',
    arrival: at(SemanticsIds.playlistAdd),
    walk: async (page) => {
      // Playlists lives under the Music hub in a section that stays
      // closed until it holds where you are, so the disclosure comes
      // first. clickThrough makes that idempotent.
      await clickThrough(
        page.locator(sem(SemanticsIds.navDisclose('music'))),
        page.locator(sem(SemanticsIds.navDestination('playlists'))),
      );
      await clickThrough(
        page.locator(sem(SemanticsIds.navDestination('playlists'))),
        page.locator(sem(SemanticsIds.playlistAdd)),
      );
    },
  },
  podcasts: {
    path: '/podcasts',
    arrival: at(SemanticsIds.podcastAdd),
    walk: railTo('podcasts', at(SemanticsIds.podcastAdd)),
  },
  books: {
    path: '/books',
    arrival: at(SemanticsIds.booksHub),
    walk: railTo('books', at(SemanticsIds.booksHub)),
  },
  radio: {
    path: '/radio',
    arrival: at(SemanticsIds.radioHub),
    walk: railTo('radio', at(SemanticsIds.radioHub)),
  },
  downloads: {
    path: '/downloads',
    arrival: at(SemanticsIds.downloadsScreen),
    walk: railTo('downloads', at(SemanticsIds.downloadsScreen)),
    walkNeeds: 'the sidebar hides Downloads until the account has one',
  },
  stats: {
    path: '/stats',
    // The range chips, at the top of the screen. Not the listen-log door
    // further down: Flutter publishes a semantics node for what is laid
    // out, so a control below the fold is not there to wait for.
    arrival: (page) => page.locator(sem(SemanticsIds.statsRange('30d'))),
    walk: railTo('stats', (page) => page.locator(sem(SemanticsIds.statsRange('30d')))),
  },
  queue: {
    path: '/queue',
    arrival: at(SemanticsIds.queueScreen),
  },
  settings: {
    path: '/settings',
    arrival: at(SemanticsIds.settingsScreen),
    walk: railTo('settings', at(SemanticsIds.settingsScreen)),
  },
  uploads: {
    path: '/uploads',
    arrival: at(SemanticsIds.uploadsScreen),
    walk: curationTo('uploads', at(SemanticsIds.uploadsScreen)),
  },
  admin: {
    path: '/admin',
    arrival: at(SemanticsIds.adminConsole),
    walk: curationTo('admin', at(SemanticsIds.adminConsole)),
  },
  // The console's own sections. Their walk is the console's section
  // list rather than the nav rail, so it goes through /admin first -
  // which is also what a person does.
  adminUsers: adminSection('users', '/admin/users', SemanticsIds.adminUsers),
  adminLibraries: adminSection('libraries', '/admin/libraries', SemanticsIds.adminLibraries),
  adminReview: adminSection('review', '/admin/review', SemanticsIds.adminReview),
  adminSettings: adminSection('settings', '/admin/settings', SemanticsIds.adminSettingsSection),
  adminAudit: adminSection('audit', '/admin/audit', SemanticsIds.adminAudit),
  adminTrash: adminSection('trash', '/admin/trash', SemanticsIds.adminTrash),
  adminBackups: adminSection('backups', '/admin/backups', SemanticsIds.adminBackups),
  adminSchedules: adminSection('schedules', '/admin/schedules', SemanticsIds.adminSchedules),
  adminGenres: adminSection('genres', '/admin/genres', SemanticsIds.adminGenres),
} satisfies Record<string, Dest>;

export type Destination = keyof typeof DEST;

export class Nav {
  constructor(private readonly page: Page) {}

  /// Open a destination cold, by its own location. The default way into
  /// a spec: one boot, no assumptions about the chrome.
  async enter(dest: Destination, options: { within?: number } = {}): Promise<void> {
    const entry: Dest = DEST[dest];
    await this.page.goto(entry.path);
    await entry.arrival(this.page).waitFor({ timeout: options.within ?? T.nav });
  }

  /// Walk there through the app's own chrome. For the specs where
  /// getting there IS the assertion - and for driver-smoke, which walks
  /// the whole table.
  async to(dest: Destination, options: { within?: number } = {}): Promise<void> {
    const entry: Dest = DEST[dest];
    if (entry.walk === undefined) {
      throw new Error(
        `dest ${dest} has no chrome walk; it is reached from a screen, ` +
          `not from the nav - use enter('${dest}') or the surface that opens it`,
      );
    }
    await this.ensureChrome();
    await entry.walk(this.page);
    await entry.arrival(this.page).waitFor({ timeout: options.within ?? T.nav });
  }

  /// The player, the queue, the visualizer and car mode are pushed over
  /// the shell, and while one is up the chrome's handles are gone from
  /// the semantics tree entirely - so a walk from there spends its whole
  /// budget finding nothing. Leaves whatever is on top, if anything is.
  ///
  /// Also boots the app when nothing has opened it yet. A test whose
  /// first action is a walk has a page still sitting on about:blank,
  /// where there is no chrome to leave and no destination to click, and
  /// the failure it produces - a nav row that never appears - reads as a
  /// missing control rather than as a missing page.
  async ensureChrome(): Promise<void> {
    // Anything that is not an http(s) document is a page nothing has
    // opened yet - about:blank, in practice. Matched on the prefix
    // rather than on `protocol === 'http:'`, because WAXDECK_BASE_URL
    // may well be https (a local TLS proxy, a staging box) and that
    // spelling would send every walk back to home.
    if (!this.page.url().startsWith('http')) {
      await this.enter('home');
      return;
    }
    const back = this.page.locator(sem(SemanticsIds.playerBack));
    if (await back.isVisible().catch(() => false)) {
      await clickThrough(back, this.page.locator(sem(SemanticsIds.navRegion)));
      return;
    }
    const close = this.page.locator(sem(SemanticsIds.panelClose));
    if (await close.isVisible().catch(() => false)) {
      await clickThrough(close, this.page.locator(sem(SemanticsIds.navRegion)));
    }
  }

  /// The account menu in the nav, which is where signing out and the
  /// account rows live.
  async accountMenu(): Promise<Locator> {
    await this.ensureChrome();
    await clickThrough(
      this.page.locator(sem(SemanticsIds.navAccount)),
      this.page.locator(sem(SemanticsIds.navAccountAction('settings'))),
    );
    return this.page.locator(sem(SemanticsIds.navAccountAction('settings')));
  }

  /// Assert where the app says it is. The `page` a spec holds is
  /// narrowed and cannot satisfy `expect(page).toHaveURL`, which is
  /// deliberate: a URL assertion belongs to the route table, so that a
  /// path that moves is one edit here.
  async expectAt(dest: Destination): Promise<void> {
    const { path } = DEST[dest];
    await expect
      .poll(() => new URL(this.page.url()).pathname, {
        timeout: T.assert,
        message: `the address bar should read ${path}`,
      })
      .toBe(path);
  }

  /// The location the app is showing, for a spec that captures a
  /// shareable link and opens it again.
  location(): string {
    return this.page.url();
  }

  /// The browser's own Back button, and what should be behind it.
  ///
  /// Worth driving rather than approximating with another `enter`: what
  /// it tests is that the app put an entry on the history stack at all.
  /// A router that pushed where it should have gone leaves Back landing
  /// on the page before the app - which unloads the SPA, and which a
  /// re-entry can never notice.
  async back(arriveAt: Destination, options: { within?: number } = {}): Promise<void> {
    await this.page.goBack();
    await DEST[arriveAt].arrival(this.page).waitFor({ timeout: options.within ?? T.nav });
  }

  /// Re-open the current location cold. A real page load since
  /// locations moved into the path, which is exactly what makes it a
  /// test of whether the location is self-sufficient.
  ///
  /// Waits for the chrome unless told what else to wait for, because a
  /// reload that returns the moment `page.reload()` resolves hands the
  /// caller a page that has not booted Flutter yet - and the assertion
  /// after it then spends the assert tier covering a wasm boot that
  /// wants the nav tier.
  async reload(arriveAt?: Destination): Promise<void> {
    await this.page.reload();
    const arrival =
      arriveAt === undefined
        ? this.page.locator(sem(SemanticsIds.navRegion))
        : DEST[arriveAt].arrival(this.page);
    await arrival.waitFor({ timeout: T.nav });
  }

  /// Open an arbitrary location the app itself minted - a shared link, a
  /// deep link into an entity. `arrival` is what proves it landed.
  async open(location: string, arrival: Locator): Promise<void> {
    await this.page.goto(location);
    await arrival.waitFor({ timeout: T.nav });
  }
}
