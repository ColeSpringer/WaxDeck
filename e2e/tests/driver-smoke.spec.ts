import { test, expect } from './fixtures';
import { Dest, DEST, Destination, J, T } from './driver';

// The route table's e2e cousin, and the reason the rest of the suite no
// longer walks the chrome to get anywhere.
//
// Every spec used to reach its screen through the sidebar, so a shell
// restructure broke eleven of them at once and each one reported it
// differently: an element not found, a click that went nowhere, a
// timeout on a screen that never arrived. The driver's default is now a
// cold load of the destination's own path, which takes that coupling out
// of every other spec - and puts it here, where a failure says which
// destination is unreachable and nothing else fails at all.
//
// `test/route_table_test.dart` is the Dart half of this: it drives every
// location through go_router. This one drives them through the real
// server, the real bundle, and the real chrome.

const destinations = Object.keys(DEST) as Destination[];
const entry = (d: Destination): Dest => DEST[d];
const walkable = destinations.filter(
  (d) => entry(d).walk !== undefined && entry(d).walkNeeds === undefined,
);
const gated = destinations.filter((d) => entry(d).walkNeeds !== undefined);

test('every location serves its own screen cold', async ({ app }) => {
  // One app boot per destination, which is the price of proving each
  // location stands on its own - a stranger pasting the link gets the
  // screen, with no in-memory payload behind it.
  test.setTimeout(J.journey);

  const unreachable: string[] = [];
  for (const dest of destinations) {
    try {
      // The step tier per destination, not the nav tier. This loop's
      // whole value is that it names EVERY unreachable destination in
      // one run, and at 30s each a handful of failures would run the
      // test out of its own budget - which reports "test timeout" at
      // whichever one happened to be in flight and says nothing at all
      // about the rest. Five seconds is generous for a page that is
      // already served and booted; a destination that is merely slow
      // shows up as a failure here and is worth knowing about too.
      await app.nav.enter(dest, { within: T.step });
      await app.nav.expectAt(dest);
    } catch (e) {
      unreachable.push(`${dest} (${DEST[dest].path}): ${String(e).split('\n')[0]}`);
    }
  }
  expect(unreachable, 'every declared location answers with its own screen').toEqual([]);
});

test('every chrome destination is reachable by walking', async ({ app }) => {
  // One boot for the lot: walking is same-document, so this is the cheap
  // half. It is also the half that fails when the sidebar is
  // restructured, which is exactly what it is here to report.
  test.setTimeout(J.journey);
  await app.nav.enter('home');

  // Said out loud rather than skipped quietly: a destination the sidebar
  // gates is one this test does not cover, and a silent gap reads as
  // coverage.
  for (const dest of gated) {
    console.log(`driver-smoke: no chrome walk for ${dest} - ${entry(dest).walkNeeds}`);
  }

  const unreachable: string[] = [];
  for (const dest of walkable) {
    try {
      await app.nav.to(dest, { within: T.step });
      await app.nav.expectAt(dest);
    } catch (e) {
      unreachable.push(`${dest}: ${String(e).split('\n')[0]}`);
    }
  }
  expect(unreachable, 'every destination with a chrome walk is reachable through it').toEqual([]);
});
