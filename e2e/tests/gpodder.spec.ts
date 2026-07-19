import { test, expect } from '@playwright/test';
import { ADMIN_USER, authed, ensureAdmin } from './helpers';

// The gpodder compatibility journey, driven exactly like a third-party
// podcast app: app-password Basic auth, the session cookie, the
// subscription change log, and episode play positions landing in
// first-party playback state.

const FEED_URL = 'http://127.0.0.1:4421/feed.xml';

function basic(user: string, secret: string) {
  return { Authorization: 'Basic ' + Buffer.from(`${user}:${secret}`).toString('base64') };
}

test('a gpodder client syncs subscriptions and play positions', async ({ request }) => {
  test.setTimeout(120_000);
  const token = await ensureAdmin(request);

  // App passwords are the only credential the compatibility surfaces
  // accept; the login password must be refused.
  const created = await request.post('/api/v1/users/me/app-passwords', {
    ...authed(token),
    data: { label: 'gpodder e2e' },
  });
  expect(created.status()).toBe(201);
  const secret = (await created.json()).secret as string;

  const badLogin = await request.post(`/api/2/auth/${ADMIN_USER}/login.json`, {
    headers: basic(ADMIN_USER, 'wax-e2e-pass'),
  });
  expect(badLogin.status(), 'the login password never works on gpodder').toBe(401);

  const login = await request.post(`/api/2/auth/${ADMIN_USER}/login.json`, {
    headers: basic(ADMIN_USER, secret),
  });
  expect(login.status()).toBe(200);
  expect(login.headers()['set-cookie'] ?? '').toContain('sessionid');

  // Device metadata upserts like AntennaPod does on first sync.
  const device = await request.post(`/api/2/devices/${ADMIN_USER}/e2ephone.json`, {
    headers: basic(ADMIN_USER, secret),
    data: { caption: 'E2E Phone', type: 'mobile' },
  });
  expect(device.status()).toBe(200);

  // Subscription diff upload creates the show server-side.
  const up = await request.post(`/api/2/subscriptions/${ADMIN_USER}/e2ephone.json`, {
    headers: basic(ADMIN_USER, secret),
    data: { add: [FEED_URL], remove: [] },
  });
  expect(up.status()).toBe(200);
  const upBody = await up.json();
  expect(typeof upBody.timestamp).toBe('number');

  // The change log replays the add to a syncing device.
  const down = await request.get(`/api/2/subscriptions/${ADMIN_USER}/e2ephone.json?since=0`, {
    headers: basic(ADMIN_USER, secret),
  });
  expect(down.status()).toBe(200);
  expect(((await down.json()).add ?? []) as string[]).toContain(FEED_URL);

  // The simple format lists it too.
  const simple = await request.get(`/subscriptions/${ADMIN_USER}.json`, {
    headers: basic(ADMIN_USER, secret),
  });
  expect(simple.status()).toBe(200);
  expect((await simple.json()) as string[]).toContain(FEED_URL);

  // And the first-party surface sees the same subscription.
  const subs = await request.get('/api/v1/podcasts', authed(token));
  const showRow = (((await subs.json()).items ?? []) as any[]).find(
    (s) => s.show.feedUrl === FEED_URL,
  );
  expect(showRow, 'gpodder subscribe should reach the first-party surface').toBeTruthy();

  // A play action with a position: parse a real enclosure URL from the
  // feed the way a podcast app holds one.
  const feedDoc = await (await request.get(FEED_URL)).text();
  const enclosures = [...feedDoc.matchAll(/enclosure url="([^"]+)"/g)].map((m) => m[1]);
  expect(enclosures.length).toBe(3);
  const episodeUrl = enclosures[enclosures.length - 1];

  const actions = await request.post(`/api/2/episodes/${ADMIN_USER}.json`, {
    headers: basic(ADMIN_USER, secret),
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
  const echo = await request.get(
    `/api/2/episodes/${ADMIN_USER}.json?since=0&aggregated=true`,
    { headers: basic(ADMIN_USER, secret) },
  );
  expect(echo.status()).toBe(200);
  const echoed = ((await echo.json()).actions ?? []) as any[];
  const mine = echoed.find((a) => a.episode === episodeUrl);
  expect(mine?.position).toBe(90);

  // And the position landed in first-party playback state.
  const eps = await request.get(`/api/v1/podcasts/${showRow.show.pid}/episodes`, authed(token));
  const items = ((await eps.json()).items ?? []) as any[];
  let matched = false;
  for (const ep of items) {
    const st = await request.get(`/api/v1/items/${ep.pid}/play-state`, authed(token));
    if (st.ok() && (await st.json()).positionMs === 90_000) {
      matched = true;
      break;
    }
  }
  expect(matched, 'the gpodder play position should reach play-state').toBeTruthy();
});
