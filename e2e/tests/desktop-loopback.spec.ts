import { spawn, ChildProcess } from 'node:child_process';
import * as path from 'node:path';
import { test, expect } from '@playwright/test';

// The desktop loopback sign-on round trip with a real browser in the
// middle: a plain-Dart probe runs the app's genuine flow (ephemeral
// localhost listener, PKCE verifier, code exchange) and reports the
// URL it wants opened; this spec drives chromium through the identity
// provider's login form; the provider redirect chain lands on the
// probe's listener; the probe finishes the exchange and hands back the
// session it won.

const APP_DIR = path.resolve(__dirname, '..', '..', 'app', 'app');

function waitForMarker(child: ChildProcess, marker: string, timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    let buffer = '';
    const timer = setTimeout(
      () => reject(new Error(`no ${marker} from probe within ${timeoutMs}ms; output so far: ${buffer.slice(-500)}`)),
      timeoutMs,
    );
    const onData = (chunk: Buffer) => {
      buffer += chunk.toString();
      // dart run prefixes its own build chatter, so scan the whole
      // buffer for the marker rather than anchoring to line starts.
      const at = buffer.indexOf(marker + ' ');
      if (at < 0) return;
      const end = buffer.indexOf('\n', at);
      if (end < 0) return;
      clearTimeout(timer);
      child.stdout!.off('data', onData);
      resolve(buffer.slice(at + marker.length + 1, end).trim());
    };
    child.stdout!.on('data', onData);
    child.on('exit', (code) => {
      clearTimeout(timer);
      reject(new Error(`probe exited ${code} before ${marker}; output: ${buffer.slice(-500)}`));
    });
  });
}

test('desktop loopback sign-on completes through a real browser', async ({ page, request, baseURL }) => {
  const probe = spawn('dart', ['run', 'tool/oidc_loopback_probe.dart', baseURL!], {
    cwd: APP_DIR,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  try {
    // The probe binds its listener and asks for a browser.
    const startUrl = await waitForMarker(probe, 'OPEN', 120_000);
    expect(startUrl).toContain('/auth/oidc/start');
    expect(startUrl).toContain('mode=loopback');
    expect(startUrl).toContain('challenge=');

    // Play the human: through the server to the IdP's form, sign in,
    // and let the redirect chain land on the probe's localhost port.
    await page.goto(startUrl);
    await page.waitForURL(/127\.0\.0\.1:4419\/authorize/, { timeout: 30_000 });
    await page.locator('input[name="idp_username"]').fill('gandalf');
    await page.locator('input[name="idp_password"]').fill('mithrandir-e2e');
    await page.locator('button[type="submit"]').click();
    await page.waitForURL(/127\.0\.0\.1:\d+\/callback/, { timeout: 30_000 });

    // The probe's real listener answered the browser and finished the
    // exchange with its verifier.
    const result = JSON.parse(await waitForMarker(probe, 'RESULT', 60_000));
    expect(result.username).toBe('gandalf');

    // The session it won is live and registered as a device.
    const session = await request.get('/api/v1/auth/session', {
      headers: { Authorization: `Bearer ${result.token}` },
    });
    expect((await session.json()).authenticated).toBe(true);
    const sessions = await request.get('/api/v1/auth/sessions', {
      headers: { Authorization: `Bearer ${result.token}` },
    });
    const devices = (await sessions.json()).sessions as Array<{ deviceName?: string; current: boolean }>;
    expect(devices.some((s) => s.deviceName === 'Loopback Probe' && s.current)).toBe(true);
  } finally {
    probe.kill('SIGKILL');
  }
});
