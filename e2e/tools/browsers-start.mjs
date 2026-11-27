// Exits 0 when each browser named (default: the suite's Chromium) starts
// on this machine as it is. tools/ci/playwright-deps.sh asks it before it
// reaches for apt, and again after.
//
// For Chromium a launch is the whole answer: every package `playwright
// install-deps` names for it is a library its binary links, or a font,
// and no spec reads a system font (the app draws with the faces it
// serves, fonts.spec.ts, and Feishin is driven by role and text). WebKit
// and Firefox also need media plugins a launch never loads, which the
// script reads from the install-deps report instead.
//
//   node tools/browsers-start.mjs [chromium|firefox|webkit ...]

import { chromium, firefox, webkit } from '@playwright/test';

// The channel is playwright.config.ts's: the binary the specs launch.
const launchers = {
  chromium: () => chromium.launch({ channel: 'chromium' }),
  firefox: () => firefox.launch(),
  webkit: () => webkit.launch(),
};

const names = process.argv.slice(2);
let failed = false;
for (const name of names.length ? names : ['chromium']) {
  const launch = launchers[name];
  if (!launch) {
    console.error(`no browser named ${name}`);
    process.exit(2);
  }
  try {
    const browser = await launch();
    await (await browser.newPage()).goto('about:blank');
    await browser.close();
  } catch (err) {
    console.error(`${name}: ${String(err?.message ?? err)}`);
    failed = true;
  }
}
process.exit(failed ? 1 : 0);
