import { spawn, execFileSync, ChildProcess } from 'node:child_process';
import * as path from 'node:path';
import { test, expect } from './fixtures';

// The desktop loopback sign-on round trip: a plain-Dart probe runs the
// app's real flow (localhost listener, PKCE, code exchange) while this
// spec plays the human in the browser between its two output lines.

const APP_DIR = path.resolve(__dirname, '..', '..', 'app', 'app');

/// Buffers the probe's output for the child's whole life: a flowing Node
/// stream discards what nobody is listening for, and the answer arrives
/// exactly while this spec is off driving the browser.
class ProbeOutput {
  private buffer = '';
  private exit: number | null = null;
  private wake: Array<() => void> = [];

  constructor(child: ChildProcess) {
    child.stdout!.setEncoding('utf8');
    child.stdout!.on('data', (chunk: string) => {
      this.buffer += chunk;
      this.notify();
    });
    child.on('close', (code) => {
      this.exit = code ?? -1;
      this.notify();
    });
  }

  private notify(): void {
    const waiters = this.wake;
    this.wake = [];
    for (const w of waiters) w();
  }

  // dart run prefixes its own build chatter, so scan the whole buffer for
  // the marker rather than anchoring to line starts.
  private find(marker: string): string | null {
    const at = this.buffer.indexOf(marker + ' ');
    if (at < 0) return null;
    const end = this.buffer.indexOf('\n', at);
    return end < 0 ? null : this.buffer.slice(at + marker.length + 1, end).trim();
  }

  async waitFor(marker: string, timeoutMs: number): Promise<string> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const found = this.find(marker);
      if (found !== null) return found;
      if (this.exit !== null) {
        throw new Error(
          `probe exited ${this.exit} before ${marker}; output: ${this.buffer.slice(-500)}`,
        );
      }
      const left = deadline - Date.now();
      if (left <= 0) {
        throw new Error(
          `no ${marker} from probe within ${timeoutMs}ms; output so far: ${this.buffer.slice(-500)}`,
        );
      }
      await new Promise<void>((resolve) => {
        const timer = setTimeout(resolve, Math.min(left, 250));
        this.wake.push(() => {
          clearTimeout(timer);
          resolve();
        });
      });
    }
  }
}

test('desktop loopback sign-on completes through a real browser', async ({ rawPage: page, request, baseURL }) => {
  // Windows: `dart` is dart.bat, which only a shell can exec.
  const probeArgs = ['run', 'tool/oidc_loopback_probe.dart', baseURL!];
  const probe: ChildProcess =
    process.platform === 'win32'
      ? spawn(['dart', ...probeArgs].join(' '), {
          cwd: APP_DIR,
          stdio: ['ignore', 'pipe', 'pipe'],
          shell: true,
        })
      : spawn('dart', probeArgs, { cwd: APP_DIR, stdio: ['ignore', 'pipe', 'pipe'] });
  const output = new ProbeOutput(probe);
  try {
    // The probe binds its listener and asks for a browser.
    const startUrl = await output.waitFor('OPEN', 120_000);
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
    const result = JSON.parse(await output.waitFor('RESULT', 60_000));
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
    // shell:true makes the direct child cmd.exe; kill() would orphan dart.
    if (process.platform === 'win32' && probe.pid) {
      try {
        execFileSync('taskkill', ['/pid', String(probe.pid), '/T', '/F'], { stdio: 'ignore' });
      } catch {}
    } else {
      probe.kill('SIGKILL');
    }
  }
});
