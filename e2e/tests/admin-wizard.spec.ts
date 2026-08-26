import { test, expect } from './fixtures';
import { ADMIN_PASS, ADMIN_USER } from './accounts';
import { T } from './driver/budgets';
import { SemanticsIds } from './semantics-ids';

// The first-run wizard's journey over a real stack: create the
// administrator, and the console is a guided tour until the server has
// a scanned library. This runs in the `wizard` project against the
// rootless second server (run-wizard-stack.sh) - the main stack boots
// with the fixture library configured, so the wizard's entry condition
// can never hold there.
//
// One test, deliberately: the wizard is a one-shot door like the
// bootstrap it follows, and a second test on this stack would find it
// already closed.

test.use({ session: 'virgin' });

test('the wizard walks an empty server to its first scanned library', async ({
  app,
}) => {
  const status = await app.api.get('/auth/bootstrap');
  test.skip(!status.required, 'wizard stack already bootstrapped (reused dev run)');

  // Its own administrator on its own installation; the shared stack's
  // accounts are nowhere near this server.
  await app.auth.completeSetup({ username: ADMIN_USER, password: ADMIN_PASS });

  // The console is the tour: no libraries, so the dashboard cedes to
  // step one.
  await app.nav.enter('admin');
  await expect(
    app.admin.control(SemanticsIds.adminWizardStep('add-library')),
  ).toBeVisible();

  // Step one's door is the libraries screen, where the folder this
  // stack synthesized gets added. Creation starts a scan of its own.
  await app.admin.control(SemanticsIds.adminAction('add-library')).click();
  const pathMod = await import('node:path');
  await app.admin.addLibrary({
    name: 'Music',
    path: pathMod.resolve(process.cwd(), '.run-wizard', 'library-src'),
  });

  // Back on the dashboard the tour has moved on from step one, which
  // is the half the create is responsible for. Which step it moved to
  // is timing the test must not assume: the create's own scan may
  // still be running, or may already be indexed and waiting on the
  // first health sweep - a scheduled job, not something a spec waits
  // for. Both are the wizard working as specified.
  await app.nav.enter('admin');
  await expect(app.admin.control(SemanticsIds.adminWizard)).toBeVisible();
  await expect(
    app.admin.control(SemanticsIds.adminWizardStep('add-library')),
  ).toBeHidden();

  // The scan was real: the folder's files are in the library. The
  // browser's own session asks, because on a virgin stack this spec
  // holds no minted token.
  await expect
    .poll(
      async () => {
        const items = await app.auth
          .browserApi()
          .get('/library/items', { query: { limit: 5 } });
        return items.items.length;
      },
      { timeout: T.analyze },
    )
    .toBeGreaterThan(0);

  // The way out, and the half a reload used to undo: skipping is a
  // decision this device keeps, so the console comes back a console.
  await app.admin.skipWizard();
  // The distinct half: the driver waited the console tiles in, and gone
  // with them is the card itself.
  await expect(app.admin.control(SemanticsIds.adminWizard)).toBeHidden();

  await app.nav.enter('admin');
  await expect(app.admin.control(SemanticsIds.adminWizard)).toBeHidden();
  await expect(app.admin.control(SemanticsIds.adminTile('health'))).toBeVisible();
});
