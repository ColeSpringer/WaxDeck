// Getting an account into a state, without driving the UI to get there.
//
// A test whose subject is the episode-detail screen should not have to
// subscribe to a feed through the add dialog first: the subscribe
// journey is somebody else's test, and re-driving it here buys a slower
// test and a second place that breaks when the dialog changes. So the
// precondition is set through the same API the app calls, and the UI
// steps that remain are the ones the test is actually about.
//
// This is what makes per-test accounts affordable. Every test starts
// from a fresh, empty account; seeding is how it gets from there to its
// starting line in one call.
//
// The rule for what belongs here: a step is seedable when it is a
// PRECONDITION. The moment a step's own outcome is what the test
// asserts, it goes back through the UI - a test that seeds the thing it
// is checking is a test of the seeder.

import { expect } from '@playwright/test';
import type { components } from '../../api-types';
import { Api } from '../api';
import { T } from '../budgets';
import { retryCatalogBusy } from '../retry';

type SmartRule = components['schemas']['SmartRule'];

// The embedded analyzer's first pass starts about 45 seconds after the
// server boots and drains the small fixture queue quickly once it is
// running. So what this waits on is boot lag plus analysis rather than
// analysis alone, which is why it sits above `T.analyze` rather than on
// it: a property of this installation's schedule, not a kind of wait.
const SONIC_SWEEP = 120_000;

export class Seed {
  constructor(private readonly api: Api) {}

  /// Subscribe to a feed and answer the show's pid, once the server has
  /// really taken it. Polled rather than read off the create response
  /// because a subscription lands its episodes asynchronously.
  async subscribePodcast(feedUrl: string): Promise<string> {
    await this.api.post('/podcasts', { data: { url: feedUrl } });
    let pid = '';
    await expect
      .poll(
        async () => {
          // tryGet throughout this file: `expect.poll` fails outright on
          // a callback that throws rather than retrying it, so a poll
          // built on `get` turns one transient 503 into a permanent
          // failure.
          const subs = await this.api.tryGet('/podcasts');
          const hit = (subs?.items ?? []).find((s) => s.show.feedUrl === feedUrl);
          if (hit === undefined) return false;
          pid = hit.show.pid;
          // The subscription row appears when the show is cataloged; its
          // episodes arrive when the feed has been parsed, which is
          // after. Every caller wants an episode, so waiting for the row
          // alone would hand back a pid whose `episodes()` is empty and
          // fail on `episodes[0].pid` rather than here.
          const eps = await this.api.tryGet('/podcasts/{pid}/episodes', {
            path: { pid },
          });
          return (eps?.items ?? []).length > 0;
        },
        { timeout: T.fetch, message: `subscribing to ${feedUrl}` },
      )
      .toBeTruthy();
    return pid;
  }

  /// Fetch an episode to the server and wait for the worker to land it.
  async fetchEpisode(showPid: string, episodePid: string): Promise<void> {
    await this.api.post('/episodes/{pid}/fetch', { path: { pid: episodePid } });
    await expect
      .poll(
        async () => {
          const eps = await this.api.tryGet('/podcasts/{pid}/episodes', {
            path: { pid: showPid },
          });
          return (eps?.items ?? []).find((e) => e.pid === episodePid)?.downloaded ?? false;
        },
        { timeout: T.fetch, message: `fetching episode ${episodePid}` },
      )
      .toBeTruthy();
  }

  /// An episode with no bytes on the server, unfetching it if there
  /// are.
  ///
  /// A download is a catalog fact rather than an account's - one file,
  /// shared by every subscriber - so "this episode has not been fetched"
  /// is a claim about the installation, and a stack that has been run
  /// against does not honour it. Every test that means an unfetched
  /// episode names the one it wants and makes it so.
  ///
  /// Both transient refusals are waited out. An unfetch ends in a delete
  /// under the shared file-mutation lease, which a sibling's upload,
  /// rescan or trash round trip can be holding (`catalog-busy`); and the
  /// server refuses to remove a file anybody is listening to
  /// (`conflict`), which a sibling playing the same episode is. Neither
  /// is the subject here - this is a precondition - and both clear on
  /// their own. The passthrough spec's own unfetch is the opposite case
  /// and waits out only the lease.
  async unfetchEpisode(showPid: string, episodePid: string): Promise<void> {
    // An episode the listing does not carry is not "already unfetched" -
    // it is a caller naming the wrong pid, and returning quietly would
    // hand the test a downloaded episode to run its unfetched scenario
    // against. The verifier below defaults the other way for the same
    // reason: absent is never proof of the state either wants.
    const held = await this.tryEpisodes(showPid);
    const before = held.find((e) => e.pid === episodePid);
    expect(before, `episode ${episodePid} should be one of show ${showPid}'s`).toBeTruthy();
    if (!(before!.downloaded ?? false)) return;
    await retryCatalogBusy(
      () => this.api.delete('/episodes/{pid}/fetch', { path: { pid: episodePid } }),
      {
        what: `episode ${episodePid} should free for an unfetch`,
        transient: ['catalog-busy', 'conflict'],
      },
    );
    await expect
      .poll(
        // tryEpisodes, not episodes: `expect.poll` ends on a callback
        // that throws rather than retrying it, and `api.get` throws on
        // any non-2xx - so one 503 while a sibling worker rescans would
        // make this precondition permanently unmeetable.
        async () =>
          (await this.tryEpisodes(showPid)).find((e) => e.pid === episodePid)?.downloaded ??
          true,
        { timeout: T.fetch, message: `unfetching episode ${episodePid}` },
      )
      .toBe(false);
  }

  /// A per-subscription setting, for the tests whose subject is what
  /// playback does with it rather than how it is chosen.
  async podcastSettings(
    showPid: string,
    settings: { trimSilence?: boolean; speed?: number },
  ): Promise<void> {
    await this.api.put('/podcasts/{pid}/settings', {
      path: { pid: showPid },
      data: settings,
    });
  }

  /// A playlist holding the given items, in order. Answers its pid.
  async createPlaylist(name: string, pids: readonly string[] = []): Promise<string> {
    const created = await this.api.post('/playlists', {
      data: { name, kind: 'static' },
    });
    const pid = (created as { pid: string }).pid;
    if (pids.length > 0) {
      await this.api.post('/playlists/{pid}/items', {
        path: { pid },
        data: { itemPids: [...pids] },
      });
    }
    return pid;
  }

  /// A smart playlist over a rule, for a test whose subject is what the
  /// rule does rather than how it was built.
  async createSmartPlaylist(name: string, rule: SmartRule): Promise<string> {
    const created = await this.api.post('/playlists', {
      data: { name, kind: 'smart', rule },
    });
    return (created as { pid: string }).pid;
  }

  /// A playlist with this name, made only if it is not already there.
  ///
  /// For a precondition that is named rather than counted. Accounts are
  /// keyed on the test's own title, so a stack that has been reused
  /// hands this test the playlist its last run left behind, and a seeder
  /// that created another would grow one per run under a name the spec
  /// then has to disambiguate. This is the artifact-hygiene rule
  /// ADR-0050 states, as a call.
  async playlistNamed(name: string, pids: readonly string[] = []): Promise<string> {
    const hit = (await this.myPlaylists()).find((p) => p.name === name);
    return hit?.pid ?? this.createPlaylist(name, pids);
  }

  /// Every playlist this account owns, across pages.
  ///
  /// Owned, because `GET /playlists` answers with the caller's own plus
  /// every shared one: a name-matching seeder that skipped the check
  /// would hand back - or delete - a sibling account's list the moment
  /// two chose the same name. Paged, because a first-page-only lookup
  /// silently stops finding things on a stack that has been used, which
  /// turns a reuse into a duplicate create.
  private async myPlaylists(): Promise<{ pid: string; name: string }[]> {
    const owned: { pid: string; name: string }[] = [];
    let cursor: string | undefined;
    do {
      const page = await this.api.get('/playlists', {
        query: cursor === undefined ? { limit: 100 } : { limit: 100, cursor },
      });
      for (const p of page.playlists ?? []) {
        if (p.isOwner) owned.push({ pid: p.pid, name: p.name });
      }
      cursor = page.nextCursor;
    } while (cursor !== undefined);
    return owned;
  }

  /// An app password under a label this account holds exactly one of.
  ///
  /// The secret is only ever handed back at creation, so a label cannot
  /// be reused the way a playlist's name can - which leaves the cap
  /// (fifty per account) as the thing to respect. Any earlier password
  /// under this label is revoked first, so a stack somebody has been
  /// reusing for a fortnight carries one rather than fourteen, and a run
  /// that died before its cleanup costs nothing. The caller still
  /// revokes on the way out; this is what makes that best-effort rather
  /// than load-bearing.
  async appPassword(label: string): Promise<{ id: string; secret: string }> {
    const held = await this.api.get('/users/me/app-passwords');
    for (const old of (held.appPasswords ?? []).filter((p) => p.label === label)) {
      await this.api.delete('/users/me/app-passwords/{appPasswordId}', {
        path: { appPasswordId: old.id },
      });
    }
    const made = await this.api.post('/users/me/app-passwords', { data: { label } });
    return { id: made.id, secret: made.secret };
  }

  /// Remove every playlist this account holds under a name.
  ///
  /// The other half of `playlistNamed`, for the tests whose subject is
  /// the making of one: those have to run against a stack they have
  /// already run against, where their own leftovers are what the
  /// assertion would find. Called before the act as well as after it, so
  /// a run that died before its cleanup costs the next one nothing.
  async clearPlaylistsNamed(name: string): Promise<void> {
    for (const pl of (await this.myPlaylists()).filter((p) => p.name === name)) {
      await this.api.delete('/playlists/{pid}', { path: { pid: pl.pid } });
    }
  }

  /// A radio station under a name, made only if it is not there.
  ///
  /// The station library is server-global - one of the few things
  /// per-test accounts do not divide - so a name is a claim on a shared
  /// row and reuse is what keeps a stack that has been run against
  /// bounded. The stream URL has to be distinct per station because the
  /// library refuses a duplicate: two stations pointed at one file would
  /// conflict on the second create rather than on anything real.
  async radioStation(
    name: string,
    streamUrl: string,
    logoUrl?: string,
  ): Promise<string> {
    // One page is the whole library: `GET /radio/stations` takes no
    // cursor and answers no `nextCursor`, which the generated types
    // enforce - so unlike the playlist seeders beside it there is no
    // paging to miss here.
    const held = await this.api.get('/radio/stations');
    const already = (held.stations ?? []).find((s) => s.name === name);
    if (already !== undefined) return already.pid;
    const made = await this.api.post('/radio/stations', {
      data: { name, streamUrl, ...(logoUrl === undefined ? {} : { logoUrl }) },
    });
    return made.pid;
  }

  /// A song kept off the air, as the heart keeps it.
  ///
  /// Per account rather than server-global, unlike the station library,
  /// so a test's rows are its own and need no name claim.
  async radioSavedSong(stationPid: string, nowPlaying: string): Promise<string> {
    const made = await this.api.post('/radio/saved', {
      data: { stationPid, nowPlaying },
    });
    return made.pid;
  }

  /// This account's saved songs, cleared.
  ///
  /// The rows outlive a browser context, so a run against a stack this
  /// account has used before would find yesterday's saves - which the
  /// empty-state assertion is precisely about.
  /// Bounded, and by progress rather than by a round count: DELETE is
  /// absent-is-success and answers 204 for a row it did not remove, so a
  /// scoping regression would leave this spinning forever and turn a red
  /// assertion into a hung worker. A pass that removes nothing is a
  /// failure worth reading.
  async clearRadioSaved(): Promise<void> {
    for (;;) {
      const page = await this.api.get('/radio/saved', { query: { limit: 200 } });
      const songs = page.songs ?? [];
      if (songs.length === 0) return;
      for (const song of songs) {
        await this.api.delete('/radio/saved/{pid}', { path: { pid: song.pid } });
      }
      const left = (await this.api.get('/radio/saved', { query: { limit: 200 } })).songs ?? [];
      expect(
        left.length,
        'deleting saved songs should remove them; the account still holds as many',
      ).toBeLessThan(songs.length);
    }
  }

  /// Set some keys of this account's preference document, leaving the
  /// rest as they are.
  ///
  /// Read-modify-written because `PUT /users/me/prefs` replaces the
  /// whole document. That used to be a hazard - two specs writing
  /// different keys as one account was last-writer-wins over fields
  /// neither meant to touch - and is now only a shape: the document is
  /// this test's own, and what this is for is the settings a test needs
  /// to start from rather than to arrive at. The account outlives the
  /// run, so "the default" is not what a second run finds.
  async prefs(values: Record<string, unknown>): Promise<void> {
    const current = await this.api.get('/users/me/prefs');
    await this.api.put('/users/me/prefs', { data: { ...current, ...values } });
  }

  /// This account's pinned stations, cleared.
  ///
  /// Favourites live in the preference document, so they outlive a
  /// browser context and a run against a stack this test has used before
  /// would find yesterday's pin still there - which is exactly what the
  /// dial test asserts the absence of. Read-modify-written because PUT
  /// replaces the whole document.
  async clearRadioFavorites(): Promise<void> {
    const current = await this.api.get('/users/me/prefs');
    await this.api.put('/users/me/prefs', {
      data: { ...current, radioFavorites: [] },
    });
  }

  /// A resume position, as the client's own checkpoint writes it.
  async setPosition(pid: string, positionMs: number): Promise<void> {
    await this.api.put('/items/{pid}/play-state', {
      path: { pid },
      data: { positionMs },
    });
  }

  /// Star or unstar an item, for the shelves and filters that draw from
  /// it.
  async star(pid: string, starred = true): Promise<void> {
    await this.api.put('/items/{pid}/star', { path: { pid }, data: { starred } });
  }

  /// The library items this account can see, which for every minted
  /// account is the whole fixture library. The starting point for a test
  /// that needs "some track" rather than a particular one.
  async items(limit = 20): Promise<{ pid: string; title: string }[]> {
    const page = await this.api.get('/library/items', { query: { limit } });
    return (page.items ?? []).map((i) => ({ pid: i.pid, title: i.title }));
  }

  /// The embedded analyzer having swept the fixture library.
  ///
  /// Requiring both an embedding and an empty queue is what
  /// distinguishes "finished" from "not started yet": before the first
  /// sweep the queue is empty with zero coverage, which a depth check
  /// alone reads as done.
  ///
  /// A precondition rather than a subject: what the specs here assert is
  /// what the sonic surfaces answer once coverage exists, and no test
  /// owns the sweep.
  async sonicCoverage(): Promise<void> {
    await expect
      .poll(
        async () => {
          const status = await this.api.tryGet('/similarity/status');
          return (status?.embeddedTracks ?? 0) > 0 && status?.queueDepth === 0;
        },
        {
          timeout: SONIC_SWEEP,
          intervals: [2_000],
          message: 'the embedded analyzer should sweep the fixture library',
        },
      )
      .toBeTruthy();
  }

  /// The scanned fixture book, by title. Polled for the same reason
  /// `item` is: the scan finding files is not the same as the book
  /// having been assembled out of its parts.
  async book(title: string): Promise<{ pid: string; durationMs: number }> {
    let hit: { pid: string; durationMs?: number } | undefined;
    await expect
      .poll(
        async () => {
          const page = await this.api.tryGet('/library/items', {
            query: { mediaType: 'audiobook' },
          });
          hit = (page?.items ?? []).find((it) => it.title === title);
          return hit !== undefined;
        },
        { timeout: T.fetch, message: `the startup scan should index "${title}"` },
      )
      .toBe(true);
    return { pid: hit!.pid, durationMs: hit!.durationMs ?? 0 };
  }

  /// Every bookmark this account holds on a book, gone.
  ///
  /// The marks are per-listener, so on a fresh account there are none -
  /// but the account is keyed on the test's title, so a stack this test
  /// has already run against hands it last run's. A test that asserts
  /// "one mark, and it says the riddle" has to start from zero.
  async clearBookmarks(bookPid: string): Promise<void> {
    const held = await this.api.get('/books/{pid}/bookmarks', { path: { pid: bookPid } });
    for (const mark of held.bookmarks ?? []) {
      await this.api.delete('/books/{pid}/bookmarks/{bookmarkId}', {
        path: { pid: bookPid, bookmarkId: mark.id },
      });
    }
  }

  /// The episodes of a subscribed show, in the server's order.
  async episodes(showPid: string) {
    const eps = await this.api.get('/podcasts/{pid}/episodes', { path: { pid: showPid } });
    return eps.items ?? [];
  }

  /// The same, for use inside a poll: answers an empty list rather than
  /// throwing, because `expect.poll` ends on a throwing callback instead
  /// of retrying it.
  async tryEpisodes(showPid: string) {
    const eps = await this.api.tryGet('/podcasts/{pid}/episodes', {
      path: { pid: showPid },
    });
    return eps?.items ?? [];
  }

  /// One item by title, for a test that means a specific fixture.
  ///
  /// Polled rather than read once. `libraryReady` proves the scan found
  /// files, which is not the same as the search index having caught up
  /// with them, and the difference is a cold stack failing in whichever
  /// spec happened to ask first - as "the fixture library should hold
  /// Alpha Song", which reads like a broken fixture rather than a race.
  async item(title: string): Promise<{ pid: string; title: string }> {
    let hit: { pid: string; title: string } | undefined;
    await expect
      .poll(
        async () => {
          const found = await this.api.tryGet('/library/search', { query: { q: title } });
          // The exact title, not the top hit. This is a search over a
          // server-global catalog that a reused stack has been adding
          // uploads to since forever, and ranking is not a contract: if
          // "Alpha Song (Remaster)" ever ranks first, taking [0] writes
          // this test's listens, positions and stars onto somebody
          // else's pid and asserts about it happily. `book` has always
          // matched on the title; this is the same rule.
          hit = (found?.tracks ?? []).find((t) => t.title === title);
          return hit !== undefined;
        },
        { timeout: T.fetch, message: `the fixture library should hold "${title}"` },
      )
      .toBe(true);
    return { pid: hit!.pid, title: hit!.title };
  }
}
