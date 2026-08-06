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
import { Api } from '../api';
import { T } from '../budgets';

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

  /// The episodes of a subscribed show, in the server's order.
  async episodes(showPid: string) {
    const eps = await this.api.get('/podcasts/{pid}/episodes', { path: { pid: showPid } });
    return eps.items ?? [];
  }

  /// One item by title, for a test that means a specific fixture.
  async item(title: string): Promise<{ pid: string; title: string }> {
    const found = await this.api.get('/library/search', { query: { q: title } });
    const hit = (found.tracks ?? [])[0];
    expect(hit, `the fixture library should hold "${title}"`).toBeTruthy();
    return { pid: hit!.pid, title: hit!.title };
  }
}
