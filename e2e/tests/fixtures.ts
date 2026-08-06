import {
  test as base,
  expect,
  APIRequestContext,
  BrowserContext,
  Page,
  PlaywrightTestArgs,
  PlaywrightTestOptions,
  PlaywrightWorkerArgs,
  PlaywrightWorkerOptions,
  TestInfo,
  TestType,
} from '@playwright/test';
import { attachBuffers, captureHangEvidence, HEARTBEAT_INIT } from './support/hangprobe';
import {
  Account,
  accountName,
  ensureAdmin,
  mintAccount,
  NO_ACCOUNT,
  shapeFor,
  signInDevice,
} from './accounts';
import { App, createApp } from './driver';
import { Api } from './driver/api';
import { T } from './driver/budgets';

export * from '@playwright/test';

// Specs import { test, expect } from './fixtures' instead of
// '@playwright/test': the page every test receives carries a rAF
// heartbeat and buffered console/error listeners from birth, and a test
// that fails or times out dumps hang evidence (thread states, worker
// responsiveness, compositor liveness) next to its trace before the
// context closes. Purpose and format: tests/hangprobe.ts and the
// renderer-hang entry in docs/deferred-work.md.
// The app ships skwasm single-threaded until flutter/flutter#190039 is
// fixed (see web/index.html). WAXDECK_E2E_MT_SKWASM=1 rewrites the
// served page to turn multi-threading back on for the run, which is
// how a new engine gets re-tested against the heap race without
// touching the app; expect the old hang rate if the bug is still
// there.
const forceMtSkwasm = !!process.env.WAXDECK_E2E_MT_SKWASM;

const isPerfSpec = (file: string) =>
  /^perf-.*\.spec\.ts$/.test(file.split(/[\\/]/).pop() ?? '');

// Once per worker: the page really is in the motion mode its project
// declared.
//
// Every blocking project runs the app under prefers-reduced-motion, and
// the whole point is that a class of failure - clicking at a rect that
// is still travelling - stops existing. That premise is invisible when
// it breaks: nothing fails, the animations simply come back and the
// flake with them. So the emulation is asserted rather than assumed, at
// the front of a test, where the message names the cause. What it
// checks is the channel this suite controls - the config asked, the
// browser answered - and not whether Flutter still reads the query;
// motion-smoke's opposite mode is the other half of that pair.
//
// about:blank is enough: the media query is emulated per context, so it
// answers before any navigation and costs no page load.
const declaredMotion = (testInfo: TestInfo) =>
  (testInfo.project.metadata as { motion?: string }).motion;

let motionChecked = false;

async function checkMotionMode(page: Page, testInfo: TestInfo) {
  if (motionChecked) return;
  motionChecked = true;
  const declared = declaredMotion(testInfo);
  expect(declared, `project ${testInfo.project.name} declares a motion mode`).toBeDefined();
  const observed = await page.evaluate(() =>
    matchMedia('(prefers-reduced-motion: reduce)').matches ? 'reduce' : 'no-preference',
  );
  expect(observed, `project ${testInfo.project.name} runs the browser in its declared motion mode`)
    .toBe(declared);
}

/// The page fixture every test gets, migrated or not.
const instrumentedPage = async (
  { page }: { page: Page },
  use: (page: Page) => Promise<void>,
  testInfo: TestInfo,
) => {
  // Not in the perf specs: a self-rescheduling rAF loop requests a
  // frame every frame, defeating idle throttling and adding a
  // callback to each frame whose pacing those specs exist to measure.
  //
  // Belt to the perf specs' braces rather than the thing that saves
  // them: they build their own contexts off `browser` and never
  // request this fixture, so nothing here runs for them today. This
  // catches the perf spec that does take a `page` - matched on the
  // basename by prefix, so a new one inherits it, and split on either
  // separator because `testInfo.file` is an absolute platform path.
  if (!isPerfSpec(testInfo.file)) {
    await page.addInitScript(HEARTBEAT_INIT);
  }
  if (forceMtSkwasm) {
    await page.route('**/*', async (route) => {
      if (route.request().resourceType() !== 'document') return route.fallback();
      const resp = await route.fetch();
      const body = (await resp.text()).replace(
        'forceSingleThreadedSkwasm: true',
        'forceSingleThreadedSkwasm: false',
      );
      await route.fulfill({ response: resp, body });
    });
  }
  await checkMotionMode(page, testInfo);
  const buffers = attachBuffers(page);
  await use(page);
  if (testInfo.status === 'timedOut' || testInfo.status === 'failed') {
    // Bounded as a whole: teardown shares the test's grace budget,
    // and a wedged probe must not eat the trace teardown behind it.
    await Promise.race([
      captureHangEvidence(page, testInfo, buffers).catch((e) =>
        console.log(`hangprobe failed: ${e}`),
      ),
      new Promise((resolve) => setTimeout(resolve, 25_000)),
    ]);
  }
};

/// What a spec may do with the page directly.
///
/// Everything else - finding a control, clicking it, going somewhere -
/// belongs to the driver, and the way that is enforced is by not handing
/// out a type that can do it. `page.locator(...)` in a migrated spec is
/// a compile error at the call site, in the editor, before anything
/// runs; `npm run typecheck` is already a step of `make e2e` and of CI.
///
/// The members here are the ones a driver cannot own on a spec's behalf:
/// the viewport is a property of the run, network waits are assertions
/// about traffic rather than about the UI, `evaluate` reaches for
/// browser state that no widget publishes, and `request` is the session
/// cookie's own hand for the few specs that mean the cookie.
export type SpecPage = Pick<
  Page,
  | 'setViewportSize'
  | 'viewportSize'
  | 'waitForRequest'
  | 'waitForResponse'
  | 'waitForEvent'
  | 'on'
  | 'off'
  | 'evaluate'
  | 'request'
  | 'video'
>;

/// How this test's browser starts, for the few specs whose subject is
/// the door itself.
///
/// - `planted` (the default): the account's session cookie is in the jar
///   before the first navigation, so the app boots signed in. What every
///   spec that is about something else wants.
/// - `signed-out`: the account exists and the browser has never heard of
///   it, so the app lands on the login form. For the specs that drive
///   that form - the walking skeleton, the accessibility walk, the
///   sign-up path, the identity scenarios.
/// - `virgin`: no account is minted and the bootstrap door is not
///   touched. Exactly one spec wants this, and it is the one whose
///   subject is a server that has no accounts yet.
export type SessionMode = 'planted' | 'signed-out' | 'virgin';

interface SpecOptions {
  /// What the browser knows about this test's account when it opens.
  /// Declared per file with `test.use({ session: ... })`.
  session: SessionMode;
}

interface SpecFixtures {
  /// The app, as something to talk to. What a migrated spec drives.
  app: App;
  /// This test's own account. Minted from its title, so it is the same
  /// account across a retry and across a run on a reused stack.
  account: Account;
  /// A second listener, on demand.
  ///
  /// For the scenarios about two people rather than one: state that must
  /// not leak between them, a permission one holds and the other does
  /// not. Named off the same test title with a suffix, so it is as
  /// stable and as bounded as the first, and minted only if asked for.
  otherAccount: (suffix?: string) => Promise<Account>;
  /// Another device signed in as this test's own account, on demand.
  ///
  /// The household case: two clients, one listener - which is what the
  /// connect and sync scenarios are about. Each gets a browser context
  /// of its own with the same session planted, and its own `App` to
  /// drive; all of them close at teardown.
  device: (options?: { as?: Account; name?: string }) => Promise<App>;
  /// The server side, typed against the contract and authenticated as
  /// `account`.
  api: Api;
  /// The server as a stranger sees it: its own request context, its own
  /// cookie jar, never logged in.
  ///
  /// `app.api.as('')` drops the bearer but keeps the connection, so once
  /// anything on that hand has logged in it carries a session cookie -
  /// "no Authorization header" rather than "unauthenticated". A spec
  /// asserting a 401 or a 403 for want of credentials means the second
  /// thing, and this is what says it.
  anonApi: Api;
  /// The real page, by name.
  ///
  /// The escape hatch for a spec the driver genuinely cannot serve. No
  /// migrated spec asks for it today, and asking is meant to be a
  /// visible choice: a file that does belongs in the exemption ledger in
  /// lint/conformance.mjs with a reason, beside the ones that are there
  /// for probing the canvas and driving a plain HTML form.
  rawPage: Page;
}

interface SpecWorkerFixtures {
  /// The bootstrap administrator's token: the minting authority, and
  /// nothing else. Worker-scoped, so the door is tried once per worker
  /// rather than once per test.
  ///
  /// A thunk rather than a value because resolving it is not free - it
  /// walks through the one-shot bootstrap door, and first-run.spec.ts is
  /// the test of that door being open. A fixture that opened it just by
  /// being in a signature would turn that spec into a permanent skip on
  /// a fresh stack, which is the one stack it has anything to say about.
  /// Memoized, so the door is still tried once per worker and no more.
  adminToken: () => Promise<string>;
  /// The startup scan having found the fixture library. Worker-scoped
  /// for the same reason: it is a property of the installation, not of
  /// a test, and it used to be polled at 42 separate call sites. A thunk
  /// for the same reason as `adminToken`, which it needs.
  libraryReady: () => Promise<void>;
}

/// Runs `work` at most once, whatever the arrival order of its callers.
const once = <T>(work: () => Promise<T>): (() => Promise<T>) => {
  let started: Promise<T> | undefined;
  return () => (started ??= work());
};

/// `baseURL` is a test-scoped option, so a worker-scoped fixture cannot
/// ask for it; the resolved project carries the merged `use`, which is
/// the same value.
const workerBaseURL = (info: { project: { use: { baseURL?: string } } }) =>
  info.project.use.baseURL;

const extended = base.extend<SpecFixtures & SpecOptions, SpecWorkerFixtures>({
  session: ['planted', { option: true }],

  adminToken: [
    async ({ playwright }, use, workerInfo) => {
      let request: APIRequestContext | undefined;
      await use(
        once(async () => {
          request = await playwright.request.newContext({
            baseURL: workerBaseURL(workerInfo),
          });
          return ensureAdmin(request);
        }),
      );
      await request?.dispose();
    },
    { scope: 'worker' },
  ],

  libraryReady: [
    async ({ playwright, adminToken }, use, workerInfo) => {
      let request: APIRequestContext | undefined;
      await use(
        once(async () => {
          request = await playwright.request.newContext({
            baseURL: workerBaseURL(workerInfo),
          });
          const api = new Api(request, await adminToken());
          // tryGet, not get: `expect.poll` fails outright on a callback
          // that throws rather than retrying it, so one 503 while the
          // catalog is still coming up would take down every test in
          // this worker.
          await expect
            .poll(async () => (await api.tryGet('/library/items'))?.items?.length ?? 0, {
              timeout: T.fetch,
              message: 'the startup scan should populate the fixture library',
            })
            .toBeGreaterThanOrEqual(4);
        }),
      );
      await request?.dispose();
    },
    { scope: 'worker' },
  ],

  account: async ({ playwright, baseURL, adminToken, session }, use, testInfo) => {
    // A virgin session is a server with no accounts on it, which is the
    // whole subject of first-run.spec.ts: minting one here - or even
    // asking for the token that would - closes the door the spec exists
    // to walk through.
    if (session === 'virgin') {
      await use(NO_ACCOUNT);
      return;
    }
    const request = await playwright.request.newContext({ baseURL });
    const account = await mintAccount(
      request,
      await adminToken(),
      accountName(testInfo.titlePath, testInfo.repeatEachIndex, testInfo.project.name),
      shapeFor(testInfo.file),
    );
    await use(account);
    await request.dispose();
  },

  // The session, planted rather than driven.
  //
  // Web auth is the `waxdeck_session` cookie and nothing else: the app
  // probes `GET /auth/session` at boot and shows the shell or the login
  // form on the answer. So the cookie jar `mintAccount` already earned
  // is everything a browser needs, and handing it to the context means
  // every spec opens the app signed in - no form, no `typeInto` on two
  // fields, no thirty-second boot spent on a journey somebody else's
  // spec is the test of.
  //
  // The account's own storageState, not a fresh login: a second
  // `POST /auth/login` opens a second server-side session, and two
  // device rows per test per run pile up on a stack that is reused.
  //
  // Mutations still work: CSRF is a synchronizer token the server
  // demands from cookie-borne credentials, and the app reads it off the
  // same boot probe. Verified end to end before this was built.
  //
  // The project's own `use` options - the viewport, the motion mode -
  // still apply: inside the test runner `browser.newContext` is the
  // instrumented one, which merges them in and wires up tracing.
  context: async ({ browser, account, session }, use) => {
    const context = await browser.newContext(
      session === 'planted' ? { storageState: account.storageState } : {},
    );
    await use(context);
    await context.close();
  },

  otherAccount: async ({ playwright, baseURL, adminToken }, use, testInfo) => {
    const minted = new Map<string, Promise<Account>>();
    const contexts: APIRequestContext[] = [];
    await use((suffix = 'other') => {
      const held = minted.get(suffix);
      if (held !== undefined) return held;
      const minting = (async () => {
        const request = await playwright.request.newContext({ baseURL });
        contexts.push(request);
        return mintAccount(
          request,
          await adminToken(),
          accountName(
            [...testInfo.titlePath, suffix],
            testInfo.repeatEachIndex,
            testInfo.project.name,
          ),
          {},
        );
      })();
      minted.set(suffix, minting);
      return minting;
    });
    for (const request of contexts) await request.dispose();
  },

  device: async (
    { browser, playwright, baseURL, account, api, libraryReady, session },
    use,
  ) => {
    if (session !== 'virgin') await libraryReady();
    const opened: BrowserContext[] = [];
    const requests: APIRequestContext[] = [];
    await use(async ({ as = account, name } = {}) => {
      const deviceName = name ?? `Playwright device ${opened.length + 1}`;
      let storageState;
      if (session === 'planted' || as !== account) {
        const request = await playwright.request.newContext({ baseURL });
        requests.push(request);
        storageState = await signInDevice(request, as, deviceName);
      }
      const context = await browser.newContext(
        storageState === undefined ? {} : { storageState },
      );
      opened.push(context);
      return createApp({
        page: await context.newPage(),
        api: as === account ? api : api.as(as.token),
        account: as,
      });
    });
    for (const context of opened) await context.close();
    for (const request of requests) await request.dispose();
  },

  api: async ({ playwright, baseURL, account }, use) => {
    const request = await playwright.request.newContext({ baseURL });
    await use(new Api(request, account.token));
    await request.dispose();
  },

  anonApi: async ({ playwright, baseURL }, use) => {
    const request = await playwright.request.newContext({ baseURL });
    await use(new Api(request, ''));
    await request.dispose();
  },

  page: instrumentedPage,

  rawPage: async ({ page }, use) => {
    await use(page);
  },

  app: async ({ page, api, account, libraryReady, session }, use) => {
    // Not for a virgin session: the scan poll authenticates as the
    // bootstrap administrator, and on the stack first-run runs against
    // there is not one yet.
    if (session !== 'virgin') await libraryReady();
    await use(createApp({ page, api, account }));
  },
});

/// The narrowing is a cast because Playwright's fixture types intersect
/// rather than replace: `base.extend<{ page: SpecPage }>` would give
/// `Page & SpecPage`, which is `Page`, and no narrowing at all. The
/// value really is a `Page` at runtime - `rawPage` hands the same object
/// back to the files that are allowed one. What this changes is what a
/// spec is able to say.
export const test = extended as unknown as TestType<
  Omit<PlaywrightTestArgs & PlaywrightTestOptions, 'page'> &
    SpecFixtures &
    SpecOptions & { page: SpecPage; context: BrowserContext },
  PlaywrightWorkerArgs & PlaywrightWorkerOptions & SpecWorkerFixtures
>;
