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
    expect(enclosures.length).toBe(3);
    const episodeUrl = enclosures[enclosures.length - 1];

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
  } finally {
    await app.api.delete('/users/me/app-passwords/{appPasswordId}', {
      path: { appPasswordId: id },
    });
  }
});
