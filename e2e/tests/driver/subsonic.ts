// The Subsonic surface is somebody else's protocol - salted-hash auth
// over query strings, not the first-party contract - so it is driven
// through the raw request context, the way a real client does.
//
// One definition for every spec that speaks it. `subsonic` asserts the
// whole envelope (transport 200 and `status: ok`), because a failed
// envelope with a 200 under it is how this protocol reports errors and
// a spec that ignored it would assert against absent fields. A spec
// probing a rejection on purpose builds its own request from
// `subsonicCredentials` and reads the failure itself.

import { APIRequestContext, expect } from '@playwright/test';
import crypto from 'node:crypto';

const SALT = 'e2esalt';

/// The salted-hash query-string triple the protocol authenticates by.
export function subsonicCredentials(who: string, secret: string): string {
  const t = crypto.createHash('md5').update(secret + SALT).digest('hex');
  return `u=${encodeURIComponent(who)}&t=${t}&s=${SALT}`;
}

/// One Subsonic view call, unwrapped to its `subsonic-response`.
export async function subsonic(
  request: APIRequestContext,
  who: string,
  secret: string,
  view: string,
  extra = '',
) {
  const res = await request.get(
    `/rest/${view}?${subsonicCredentials(who, secret)}&v=1.16.1&c=e2e&f=json${extra}`,
  );
  expect(res.status()).toBe(200);
  const body = (await res.json())['subsonic-response'];
  expect(body.status).toBe('ok');
  return body;
}
