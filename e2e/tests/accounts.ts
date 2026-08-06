// One account per test, minted through the production API.
//
// The suite used to run every spec as one shared administrator. Four
// workers, one login, and so every per-user number in the system - a
// podcast backlog, a queue, a star, a play position, a preference
// document - was the sum of whatever four unrelated scenarios happened
// to be doing. The suite grew folklore to cope: serial groups,
// presence-not-absence assertions, comments in fifteen files reasoning
// about siblings. This removes the cause instead: a test that owns its
// login shares none of that, so it can assert exact counts, assert
// absence, and be retried on its own.
//
// What is deliberately NOT removed is the shared server. The catalog,
// the file-mutation lease, the event fan-out and the scan are still one
// installation under four workers, because that contention is the
// household this product is for - and it is where the real defects the
// suite has caught actually lived. Only same-login aliasing goes.
//
// No test-only server surface exists to make this cheap (ADR-0036: the
// server ships what it ships). So minting is idempotent instead:
// create-or-409-then-log-in, against a name derived from the test's own
// title. A reused stack accumulates a bounded set of accounts - one per
// test, about ninety - and a renamed test strands an inert one.

import { APIRequestContext, expect } from '@playwright/test';
import { Api } from './driver/api';
import type { components } from './api-types';

type LoginResponse = components['schemas']['LoginResponse'];
type Role = components['schemas']['Role'];

/// The bootstrap administrator. Two jobs and no others: it is the
/// subject of first-run.spec.ts, and it is the authority that mints
/// every other account. No spec logs in as it - the conformance ratchet
/// enforces that.
export const ADMIN_USER = 'admin';
export const ADMIN_PASS = 'wax-e2e-pass';

/// One password for every minted account. There is nothing to protect:
/// the stack is a fixture library on a loopback port, and a second
/// secret would only be a second thing to thread through.
export const ACCOUNT_PASS = 'wax-e2e-pass';

export interface Account {
  readonly username: string;
  readonly password: string;
  readonly token: string;
  readonly admin: boolean;
  /// The cookie jar this account's login left behind, for the browser
  /// context to plant. Carried rather than re-earned: a second
  /// `POST /auth/login` would open a second server-side session, so
  /// every test would leave two device rows behind instead of one - and
  /// on a stack that is reused across runs those add up in a list the
  /// settings screen draws.
  readonly storageState: StorageState;
}

type StorageState = Awaited<ReturnType<APIRequestContext['storageState']>>;

/// What an account needs to be, where the default will not do.
///
/// The default is a plain user with `libraryAccess: all` - which is what
/// makes the shared catalog legible to every test - and the server's own
/// default permissions (everything but delete, and `managePodcasts`
/// true). Anything else is declared here, by the file that needs it, so
/// the exceptions are a list somebody can read rather than a habit.
///
/// `admin` is the one that matters. It is server-global authority: an
/// account holding it can flip the read-only switch, edit libraries and
/// change settings every other worker shares. The set is pinned a second
/// time in lint/conformance.mjs, so adding one is a two-file edit that
/// shows up in review.
///
/// There is deliberately no file-scoped option. ADR-0050 leaves room for
/// one, for a file whose setup is expensive and cannot be replaced by
/// seeding; nothing has needed it, and a declared field that silently
/// changes nothing is worse than its absence - it reads as a lever
/// somebody has already pulled.
export interface AccountShape {
  readonly role?: 'admin';
}

export const accountShapes: Record<string, AccountShape> = {
  // Walks every destination in the table, the admin console's sections
  // among them.
  'driver-smoke': { role: 'admin' },
  // The admin console, the review queue, uploads and the notification
  // targets are administrator surfaces: the screens under test do not
  // exist for anybody else.
  'admin-ops': { role: 'admin' },
  notifications: { role: 'admin' },
  'review-queue': { role: 'admin' },
  'signup-ui': { role: 'admin' },
  uploads: { role: 'admin' },
};

/// The bootstrap administrator's token. The first caller opens the
/// one-shot door; everybody after it - and every run against a stack
/// that already exists - falls through to an ordinary login. Specs may
/// race and both outcomes converge on the same account.
export async function ensureAdmin(request: APIRequestContext): Promise<string> {
  const boot = await request.post('/api/v1/auth/bootstrap', {
    data: { username: ADMIN_USER, password: ADMIN_PASS },
  });
  if (boot.ok()) {
    return (await boot.json()).token as string;
  }
  expect(boot.status(), 'bootstrap either succeeds or reports the door closed').toBe(409);
  const login = await request.post('/api/v1/auth/login', {
    data: { username: ADMIN_USER, password: ADMIN_PASS },
  });
  expect(login.ok()).toBeTruthy();
  return (await login.json()).token as string;
}

/// A stable, legal username for a test title.
///
/// Deterministic, so a reused stack re-uses the account rather than
/// growing a new one every run, and so a retry lands on the same state
/// the first attempt left. The hash is what makes truncation safe: two
/// tests whose titles agree for the first fifty characters still get
/// different accounts.
/// `repeatEachIndex` is part of the key, not decoration. `titlePath` is
/// the file and the titles above the test and nothing else, so under
/// `--repeat-each=3` - which is exactly what the soak runs - all three
/// copies of a test would derive the same name and log in as the same
/// account. One copy asserting an untouched backlog while another has
/// already played an episode is the same-login aliasing this whole
/// module exists to remove, manufactured by the workflow built to find
/// it. A retry is deliberately NOT in the key: a retried test is meant
/// to land on the account its first attempt used.
export function accountName(
  titlePath: readonly string[],
  repeatEachIndex = 0,
): string {
  const full = repeatEachIndex === 0
    ? titlePath.join('/')
    : `${titlePath.join('/')}#${repeatEachIndex}`;
  const slug = full
    .replace(/\.spec\.ts/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  // Usernames are capped at 64. `e2e-` and a seven-character tail leave
  // 53 for the readable part, which is what makes an account in a
  // `/users` listing recognisable as the test that minted it.
  return `e2e-${slug.slice(0, 53).replace(/-+$/, '')}-${hash(full)}`;
}

/// FNV-1a, 24 bits, base36. Short enough to read, wide enough that the
/// ninety-odd names in play will not collide.
function hash(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return (h & 0xffffff).toString(36).padStart(5, '0');
}

/// Creates the account if it is not there and logs in either way.
///
/// Idempotent by construction, which is what makes it safe on a reused
/// stack, on a retry, and against a sibling worker minting the same name
/// in the same instant (both see one 201 and one 409, and both log in).
export async function mintAccount(
  request: APIRequestContext,
  adminToken: string,
  username: string,
  shape: AccountShape = {},
): Promise<Account> {
  const admin = new Api(request, adminToken);
  const created = await admin.raw.post('/users', {
    data: {
      username,
      password: ACCOUNT_PASS,
      roles: shape.role === 'admin' ? ['admin'] : ['user'],
      // Always the whole catalog. The shared library is the ground every
      // test stands on; per-library visibility is a thing identity.spec
      // tests deliberately, not a default anybody inherits.
      libraryAccess: { mode: 'all' },
    },
  });
  expect(
    created.status() === 201 || created.status() === 409,
    `minting ${username} answered ${created.status()}: ${await created.text()}`,
  ).toBeTruthy();

  // An account that already exists carries every session earlier runs
  // opened on it, and the settings screen draws that list. Cleared
  // before this run's own login, so a stack somebody has been reusing
  // for a fortnight does not hand a test a device list forty rows long
  // and the surfaces below it out of reach. A fresh account has none, so
  // this is the 409 path only.
  if (created.status() === 409) {
    const existing = await findUser(admin, username);
    if (existing !== undefined) {
      await admin.delete('/users/{userId}/sessions', { path: { userId: existing } });
    }
  }

  let session = await logIn(request, username);

  // A 409 means the account was already there, from an earlier run
  // against this same stack - and an account that already exists was
  // created under whatever shape was declared then. Names are keyed on
  // the test's title, not on its shape, so declaring `role: 'admin'` for
  // a spec that used to be a plain user leaves a stale account behind
  // that logs in perfectly well and is refused by every admin surface
  // the spec then touches. Reconciled rather than tolerated: the
  // alternative is a 403 halfway through a test on one developer's box
  // and nowhere else.
  //
  // Compared as a set rather than with `includes`, so that dropping a
  // role is reconciled as surely as gaining one: an account left holding
  // `admin` by a shape that no longer asks for it would satisfy a
  // contains-check for `user` and keep server-global authority.
  const wanted: Role[] = [shape.role ?? 'user'];
  const asSet = (roles: readonly string[]) => [...roles].sort().join(',');
  if (created.status() === 409 && asSet(session.roles) !== asSet(wanted)) {
    await admin.patch('/users/{userId}', {
      path: { userId: session.id },
      data: { roles: wanted },
    });
    session = await logIn(request, username);
    expect(
      session.roles,
      `${username} exists from an earlier run and could not be moved to ${wanted[0]}`,
    ).toEqual(wanted);
  }

  return {
    username,
    password: ACCOUNT_PASS,
    token: session.token,
    // Captured here, where the login that earned it happened. The
    // browser context plants this rather than logging in again.
    storageState: await request.storageState(),
    admin: shape.role === 'admin',
  };
}

/// An account's id by its name. `/users` offers no name filter, so this
/// walks its pages - which is affordable because it runs only when the
/// account already existed, and the set is bounded at one per test.
async function findUser(admin: Api, username: string): Promise<string | undefined> {
  let cursor: string | undefined;
  do {
    const page = await admin.get('/users', {
      query: cursor === undefined ? {} : { cursor },
    });
    const hit = page.users.find((u) => u.username === username);
    if (hit !== undefined) return hit.id;
    cursor = page.nextCursor;
  } while (cursor !== undefined);
  return undefined;
}

/// Logging in is the one call that cannot go through `driver/api.ts`:
/// that hand carries a bearer token, and this is where the token comes
/// from. The response shape is still taken from the contract rather than
/// written out here - a hand-typed copy of it is how `user.id` became
/// `user.pid` in the first draft of this function, which compiled
/// perfectly and would have sent `undefined` as a path segment.
async function logIn(request: APIRequestContext, username: string) {
  const login = await request.post('/api/v1/auth/login', {
    data: { username, password: ACCOUNT_PASS },
  });
  expect(login.ok(), `logging in as ${username}`).toBeTruthy();
  const body = (await login.json()) as LoginResponse;
  return { token: body.token, id: body.user.id, roles: body.user.roles };
}

/// The shape declared for a spec file, by its basename without the
/// extension - `accountShapes['review-queue']` for review-queue.spec.ts.
export function shapeFor(file: string): AccountShape {
  const base = (file.split(/[\\/]/).pop() ?? '').replace(/\.spec\.ts$/, '');
  return accountShapes[base] ?? {};
}
