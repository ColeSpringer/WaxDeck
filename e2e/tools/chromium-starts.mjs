// Exits 0 when the suite's Chromium starts on this machine as it is;
// tools/ci/playwright-deps.sh asks before it reaches for apt.
//
// A launch answers it: every package `playwright install-deps` names
// for Chromium is a library the binary links directly, so a missing one
// fails the exec, or a font, and no spec reads a system font. The app
// draws with the faces it serves (fonts.spec.ts) and Feishin is driven
// by role and text.

import { chromium } from '@playwright/test';

try {
  // The channel is playwright.config.ts's: the binary the specs launch.
  const browser = await chromium.launch({ channel: 'chromium' });
  await (await browser.newPage()).goto('about:blank');
  await browser.close();
} catch (err) {
  console.error(String(err?.message ?? err));
  process.exit(1);
}
