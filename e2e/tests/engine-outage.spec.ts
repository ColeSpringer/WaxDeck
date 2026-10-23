import { execFileSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { test, expect } from './fixtures';
import { J, T } from './driver';
import { MediaTraffic } from './support/media';

// The streaming engine stopped under the running stack and continued
// again. SIGSTOP leaves the sidecar's port open with its answers never
// coming, the harder of the two ways to be away: the server notices
// within its probe interval, serves originals directly meanwhile,
// answers a stream minted before the outage from the original's bytes,
// and takes the engine back once it answers. A project of its own:
// nothing else may be streaming through the engine while it is stopped.
test.describe.configure({ mode: 'serial' });

/// The pid run-stack.sh wrote for the sidecar it started, and removes
/// when the stack exits.
const PID_FILE = path.join(__dirname, '..', '.run', 'sidecar.pid');

/// The sidecar this run started, or 0 and why there is none to stop: only
/// that process is ever signalled, never whatever a stale pid names now.
function sidecarPid(): { pid: number; why: string } {
  const none = (why: string) => ({ pid: 0, why });
  if (process.env.WAXDECK_BASE_URL) return none('the stack under test is not the one run-stack.sh started');
  if (!fs.existsSync(PID_FILE)) return none('the stack was not started by run-stack.sh');
  const pid = Number(fs.readFileSync(PID_FILE, 'utf8').trim());
  if (!Number.isInteger(pid) || pid <= 0) return none(`${PID_FILE} names no process`);
  let name = '';
  try {
    // /proc where there is one, ps elsewhere; either fails for a pid
    // that is gone.
    name = fs.existsSync('/proc')
      ? fs.readFileSync(`/proc/${pid}/comm`, 'utf8')
      : execFileSync('ps', ['-p', String(pid), '-o', 'comm='], { encoding: 'utf8' });
  } catch {
    return none(`the sidecar pid ${pid} is not running`);
  }
  if (path.basename(name.trim()) !== 'waxflow-catalog') {
    return none(`pid ${pid} is ${name.trim() || 'unnamed'}, not the sidecar`);
  }
  return { pid, why: '' };
}

test('originals play while the streaming engine is away', async ({ app }) => {
  // Boot, a probe interval to notice the loss, a cold album start, then a
  // backed-off probe to notice the return: more than the default allows.
  test.setTimeout(J.long);
  test.skip(process.platform === 'win32', 'a process cannot be stopped and continued on Windows');
  const { pid: sidecar, why } = sidecarPid();
  test.skip(sidecar === 0, why);
  const connected = async () => (await app.api.get('/health')).streaming?.connected;
  await expect.poll(connected, { message: 'the engine should answer to begin with', timeout: T.fetch }).toBe(true);

  const traffic = await MediaTraffic.watch(app.page);
  const { pid } = await app.seed.item('Alpha Song');
  await app.seed.setPosition(pid, 0);
  const before = await app.api.get('/items/{pid}/play-info', { path: { pid } });
  expect(before.url, 'a stream through the engine while it answers').toContain('/media/stream?');

  process.kill(sidecar, 'SIGSTOP');
  try {
    // Within the probe interval and one ask's wait.
    await expect
      .poll(connected, { message: 'the probe should find the engine away', timeout: T.nav })
      .toBe(false);

    const during = await app.api.get('/items/{pid}/play-info', { path: { pid } });
    expect(during.url, 'the original, directly').toMatch(/^\/media\/download\?/);
    // Minted before the outage, and still the original's bytes.
    const carried = await app.api.raw.minted(before.url);
    expect(carried.status(), 'a stream minted before the outage').toBe(200);
    expect((await carried.body()).byteLength).toBeGreaterThan(1000);

    // The player starts the original from the direct url and plays it,
    // skipping nothing.
    const started = traffic.mark();
    await app.music.playAlbumOf(pid);
    await expect(app.player.deckToggle()).toHaveAccessibleName(/Pause/i);
    await expect
      .poll(() => traffic.furthest(pid), { message: 'the original should play while the engine is away' })
      .toBeGreaterThan(0.25);
    const mints = traffic.mints(pid).filter((m) => m.seq > started);
    expect(mints.length, 'the player asked for the item').toBeGreaterThan(0);
    for (const mint of mints) {
      expect(mint.url, 'every mint while away is the direct url').toMatch(/^\/media\/download\?/);
    }
    await expect(app.player.text(/Skipped/)).toHaveCount(0);
  } finally {
    process.kill(sidecar, 'SIGCONT');
  }

  await expect
    .poll(connected, { message: 'the engine should be taken back once it answers', timeout: T.fetch })
    .toBe(true);
  const after = await app.api.get('/items/{pid}/play-info', { path: { pid } });
  expect(after.url, 'a stream through the engine again').toContain('/media/stream?');
});
