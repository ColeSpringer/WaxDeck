import { test, expect, Page } from './fixtures';
import { T } from './driver/budgets';
import { clickToward, rectAtRest } from './driver/gestures';
import {
  measureThemeSwitchPacing,
  reportThemeSwitchPacing,
} from './support/scroll-pacing';
import { SemanticsIds, sem } from './semantics-ids';

// Frame pacing across a theme switch, run on demand:
//
//   PERF_THEME_SWITCH=1 npx playwright test perf-theme-switch
//
// Two surfaces: the settings screen, where the theme is picked through its
// own control, and a grid of many cards, where the switch comes from the
// system appearance flipping under a theme that follows it - the picker only
// lives on settings, and a system flip takes the same path through the app.
// Measured values print for the record; there is no budget.
//
// The context runs with motion unreduced: the blocking projects reduce it,
// and Flutter then scales every animation down to a twentieth, which would
// leave no fade to measure.
const enabled = !!process.env.PERF_THEME_SWITCH;

const CARDS = 60;

async function noPreferenceMotion(page: Page): Promise<boolean> {
  return page.evaluate(() => !matchMedia('(prefers-reduced-motion: reduce)').matches);
}

// A frame count means nothing if the theme never changed, so each switch
// is held to having redrawn the screen. Returns the new picture to compare
// the next switch against.
async function changed(page: Page, previous: Buffer, label: string): Promise<Buffer> {
  const now = await page.screenshot();
  expect(now.equals(previous), `${label}: the screen changed`).toBe(false);
  return now;
}

test.describe('theme switch pacing', () => {
  test.skip(!enabled, 'set PERF_THEME_SWITCH=1 to run the theme switch probe');
  test.setTimeout(300_000);

  test('frames across a theme switch on settings and on a full grid', async ({
    browser,
    account,
    api,
    libraryReady,
  }) => {
    await libraryReady();
    const made: string[] = [];
    for (let i = 0; i < CARDS; i++) {
      const created = await api.post('/playlists', {
        data: { name: `Pacing ${String(i).padStart(2, '0')}`, kind: 'static' },
      });
      made.push((created as { pid: string }).pid);
    }

    // A context per surface: the picked theme is stored on the device, and
    // a stored choice stops the app following the system.
    const open = async (body: (page: Page) => Promise<void>) => {
      const context = await browser.newContext({
        storageState: account.storageState,
        reducedMotion: 'no-preference',
        colorScheme: 'light',
      });
      try {
        const page = await context.newPage();
        expect(await noPreferenceMotion(page), 'motion is not reduced in this context').toBe(
          true,
        );
        await body(page);
      } finally {
        await context.close();
      }
    };

    try {
      console.log('perf-theme-switch pacing, 400ms window');

      // Settings: the theme picked from its own menu.
      await open(async (page) => {
        await page.goto('/settings/appearance');
        const trigger = page.locator(sem(SemanticsIds.themeSelect));
        await trigger.waitFor({ timeout: T.nav });
        let shown = await page.screenshot();
        for (const theme of ['dark', 'light']) {
          const option = page.locator(sem(SemanticsIds.settingOption('theme', theme)));
          await clickToward(trigger, { shows: option });
          await rectAtRest(option);
          const pacing = await measureThemeSwitchPacing(page, () =>
            option.click({ force: true }),
          );
          reportThemeSwitchPacing(`settings -> ${theme}`, pacing);
          shown = await changed(page, shown, `settings -> ${theme}`);
        }
      });

      // The grid: the theme follows the system, which flips under it.
      await open(async (page) => {
        await page.goto('/playlists');
        const onScreen = async () => {
          let n = 0;
          for (const pid of made) {
            if ((await page.locator(sem(SemanticsIds.playlist(pid))).count()) > 0) n++;
          }
          return n;
        };
        await expect.poll(onScreen, { timeout: T.nav }).toBeGreaterThan(12);
        console.log(`  grid cards on screen: ${await onScreen()}`);
        let shown = await page.screenshot();
        for (const scheme of ['dark', 'light'] as const) {
          const pacing = await measureThemeSwitchPacing(page, () =>
            page.emulateMedia({ colorScheme: scheme }),
          );
          reportThemeSwitchPacing(`grid -> ${scheme}`, pacing);
          await expect.poll(onScreen, { timeout: T.step }).toBeGreaterThan(12);
          shown = await changed(page, shown, `grid -> ${scheme}`);
        }
      });
    } finally {
      for (const pid of made) await api.delete('/playlists/{pid}', { path: { pid } });
    }
  });
});
