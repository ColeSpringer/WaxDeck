import { test, expect } from './fixtures';

// The gpodder compatibility journey, driven exactly like a third-party
// podcast app: app-password Basic auth, the session cookie, the
// subscription change log, and episode play positions landing in
// first-party playback state.
//
// The gpodder surfaces are not in `api/openapi.yaml` - they are somebody
// else's protocol, which is the whole point of implementing them - so
// they are driven through the raw request context rather than through
// the typed hand. The first-party half beside them is typed.

const FEED_URL = 'http://127.0.0.1:4421/feed.xml';
const EARLY_FEED = 'http://127.0.0.1:4421/early/feed.xml';

function basic(user: string, secret: string) {
  return { Authorization: 'Basic ' + Buffer.from(`${user}:${secret}`).toString('base64') };
}

test('a gpodder client syncs subscriptions and play positions', async ({
  app,
  request,
}) => {
  const who = app.account.username;
  // App passwords are the only credential the compatibility surfaces
  // accept; the login password must be refused.
  const { id, secret } = await app.seed.appPassword('gpodder e2e');
  try {
    const badLogin = await request.post(`/api/2/auth/${who}/login.json`, {
      headers: basic(who, app.account.password),
    });
    expect(badLogin.status(), 'the login password never works on gpodder').toBe(401);

    const login = await request.post(`/api/2/auth/${who}/login.json`, {
      headers: basic(who, secret),
    });
    expect(login.status()).toBe(200);
    expect(login.headers()['set-cookie'] ?? '').toContain('sessionid');

    // Device metadata upserts like AntennaPod does on first sync.
    const device = await request.post(`/api/2/devices/${who}/e2ephone.json`, {
      headers: basic(who, secret),
      data: { caption: 'E2E Phone', type: 'mobile' },
    });
    expect(device.status()).toBe(200);

    // Subscription diff upload creates the show server-side.
    const up = await request.post(`/api/2/subscriptions/${who}/e2ephone.json`, {
      headers: basic(who, secret),
      data: { add: [FEED_URL], remove: [] },
    });
    expect(up.status()).toBe(200);
    expect(typeof (await up.json()).timestamp).toBe('number');

    // The change log replays the add to a syncing device. Exact, because
    // this account's subscription log is its own - what it used to have
    // to tolerate was the podcasts spec subscribing under the same
    // login.
    const down = await request.get(`/api/2/subscriptions/${who}/e2ephone.json?since=0`, {
      headers: basic(who, secret),
    });
    expect(down.status()).toBe(200);
    expect(((await down.json()).add ?? []) as string[]).toEqual([FEED_URL]);

    // The simple format lists it too.
    const simple = await request.get(`/subscriptions/${who}.json`, {
      headers: basic(who, secret),
    });
    expect(simple.status()).toBe(200);
    expect((await simple.json()) as string[]).toEqual([FEED_URL]);

    // And the first-party surface sees the same subscription.
    const subs = await app.api.get('/podcasts');
    const showRow = (subs.items ?? []).find((s) => s.show.feedUrl === FEED_URL);
    expect(showRow, 'gpodder subscribe should reach the first-party surface').toBeTruthy();

    // A play action with a position: parse a real enclosure URL from the
    // feed the way a podcast app holds one.
    const feedDoc = await (await request.get(FEED_URL)).text();
    const enclosures = [...feedDoc.matchAll(/enclosure url="([^"]+)"/g)].map((m) => m[1]);
    expect(enclosures.length).toBe(4);
    // Not the last: that one is never touched (podcasts.spec.ts).
    const episodeUrl = enclosures[2];

    const actions = await request.post(`/api/2/episodes/${who}.json`, {
      headers: basic(who, secret),
      data: [
        {
          podcast: FEED_URL,
          episode: episodeUrl,
          action: 'play',
          device: 'e2ephone',
          timestamp: '2026-07-18T10:00:00',
          started: 0,
          position: 90,
          total: 300,
        },
      ],
    });
    expect(actions.status()).toBe(200);

    // The action echoes back aggregated.
    const echo = await request.get(`/api/2/episodes/${who}.json?since=0&aggregated=true`, {
      headers: basic(who, secret),
    });
    expect(echo.status()).toBe(200);
    const echoed = ((await echo.json()).actions ?? []) as { episode: string; position: number }[];
    expect(echoed.find((a) => a.episode === episodeUrl)?.position).toBe(90);

    // And the position landed in first-party playback state.
    const eps = await app.api.get('/podcasts/{pid}/episodes', {
      path: { pid: showRow!.show.pid },
    });
    const positions = await Promise.all(
      (eps.items ?? []).map(async (ep) =>
        (await app.api.tryGet('/items/{pid}/play-state', { path: { pid: ep.pid } }))
          ?.positionMs,
      ),
    );
    expect(positions, 'the gpodder play position should reach play-state').toContain(90_000);

    // The login's cookie authenticates on its own, and dies with the app
    // password that opened it.
    const cookie = (login.headers()['set-cookie'] ?? '').split(';')[0];
    const withCookie = () =>
      request.get(`/api/2/devices/${who}.json`, { headers: { Cookie: cookie } });
    expect((await withCookie()).status()).toBe(200);
    await app.api.delete('/users/me/app-passwords/{appPasswordId}', {
      path: { appPasswordId: id },
    });
    expect((await withCookie()).status(), 'the cookie after its app password was revoked').toBe(401);
  } finally {
    // Gone already on the passing path; this is for the failing one.
    await app.api.raw.delete('/users/me/app-passwords/{appPasswordId}', {
      path: { appPasswordId: id },
    });
  }
});

// A full-list upload replaces only the uploading device's own list: what
// the web app follows and what another device added stay, and an empty
// list from a device that never held them takes nothing.
test("a second device's full list does not unsubscribe the first", async ({
  app,
  request,
}) => {
  const who = app.account.username;
  const { id, secret } = await app.seed.appPassword('gpodder e2e lists');
  try {
    await app.seed.subscribePodcast(FEED_URL);

    const phone = await request.post(`/api/2/subscriptions/${who}/e2ephone.json`, {
      headers: basic(who, secret),
      data: { add: [EARLY_FEED], remove: [] },
    });
    expect(phone.status()).toBe(200);
    expect(((await phone.json()).update_urls ?? []) as string[][]).toEqual([]);

    // The desk's "replace list on server", naming only the phone's show,
    // then nothing at all.
    const replace = await request.put(`/subscriptions/${who}/e2edesk.txt`, {
      headers: { ...basic(who, secret), 'Content-Type': 'text/plain' },
      data: `${EARLY_FEED}\n`,
    });
    expect(replace.status()).toBe(200);
    const empty = await request.put(`/subscriptions/${who}/e2edesk.json`, {
      headers: basic(who, secret),
      data: [],
    });
    expect(empty.status()).toBe(200);

    const subs = await app.api.get('/podcasts');
    const followed = (subs.items ?? []).map((s) => s.show.feedUrl);
    expect(followed, 'the web subscription survives the desk').toContain(FEED_URL);
    expect(followed, "the phone's subscription survives the desk").toContain(EARLY_FEED);

    const listed = await request.get(`/subscriptions/${who}.json`, {
      headers: basic(who, secret),
    });
    expect(listed.status()).toBe(200);
    expect((await listed.json()) as string[]).toEqual(
      expect.arrayContaining([FEED_URL, EARLY_FEED]),
    );
  } finally {
    await app.api.raw.delete('/users/me/app-passwords/{appPasswordId}', {
      path: { appPasswordId: id },
    });
  }
});
