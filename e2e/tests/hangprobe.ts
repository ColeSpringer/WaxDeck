import * as fs from 'node:fs';
import * as path from 'node:path';
import type { Page, TestInfo } from '@playwright/test';

// Evidence collector for the one remaining flake: a renderer hang in the
// wasm rendering path (docs/deferred-work.md). Playwright's trace shows
// the page stopped answering but nothing about which thread stopped or
// why; this closes that gap. Everything here races against a deadline —
// a probe against a hung renderer must never be awaited bare, and a
// probe promise that loses its race must carry a catch already, or its
// late rejection (when the context closes) takes down the runner.

type ProbeResult =
  | { ok: true; ms: number; value: unknown }
  | { ok: false; ms: number; err: string };

async function race(p: Promise<unknown>, ms: number): Promise<ProbeResult> {
  const started = Date.now();
  const guarded = p.then(
    (value) => ({ ok: true as const, ms: Date.now() - started, value }),
    (e) => ({ ok: false as const, ms: Date.now() - started, err: String(e).slice(0, 500) }),
  );
  const timer = new Promise<ProbeResult>((resolve) =>
    setTimeout(() => resolve({ ok: false, ms, err: `no answer in ${ms}ms` }), ms),
  );
  return Promise.race([guarded, timer]);
}

// The heartbeat the probe reads back: page-side rAF loop stamping the
// last frame callback. If the main thread hangs, evaluate can't read it
// (itself diagnostic); if the main thread is alive but presentation
// stopped, the stamps say exactly when frames ceased.
export const HEARTBEAT_INIT = `(() => {
  try {
    let n = 0;
    const loop = (t) => { window.__wax_lastRaf = t; window.__wax_rafCount = ++n; requestAnimationFrame(loop); };
    requestAnimationFrame(loop);
    window.addEventListener('error', (e) => { window.__wax_lastError = String(e.message).slice(0, 300); });
    window.addEventListener('unhandledrejection', (e) => { window.__wax_lastRejection = String(e.reason).slice(0, 300); });
  } catch {}
})();`;

interface ThreadSnap {
  tid: number;
  comm: string;
  state: string;
  wchan: string;
  cpuTicks: number;
}

interface ProcSnap {
  pid: number;
  type: string;
  threads: ThreadSnap[];
}

function readOr(file: string, fallback = ''): string {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return fallback;
  }
}

// One pass over /proc for a set of pids: per-thread name, run state,
// kernel wait channel, and cpu ticks. wchan is readable for same-uid
// processes without ptrace; two snapshots a second apart turn cpu ticks
// into "spinning" vs "parked", which is the distinction a debugger
// attach would have given us and yama's ptrace_scope=1 denies.
function snapshotPids(pids: Map<number, string>): ProcSnap[] {
  const snaps: ProcSnap[] = [];
  for (const [pid, type] of pids) {
    const taskDir = `/proc/${pid}/task`;
    let tids: string[] = [];
    try {
      tids = fs.readdirSync(taskDir);
    } catch {
      continue; // process exited between listing and reading
    }
    const threads: ThreadSnap[] = [];
    for (const tidStr of tids) {
      const tid = Number(tidStr);
      const stat = readOr(`${taskDir}/${tidStr}/stat`);
      // comm can contain spaces; it is parenthesized in stat. Parse
      // around the last ')'.
      const close = stat.lastIndexOf(')');
      if (close < 0) continue;
      const comm = stat.slice(stat.indexOf('(') + 1, close);
      const rest = stat.slice(close + 2).split(' ');
      const state = rest[0] ?? '?';
      const utime = Number(rest[11] ?? 0);
      const stime = Number(rest[12] ?? 0);
      const wchan = readOr(`${taskDir}/${tidStr}/wchan`).trim() || '-';
      threads.push({ tid, comm, state, wchan, cpuTicks: utime + stime });
    }
    snaps.push({ pid, type, threads });
  }
  return snaps;
}

// Every chromium process this user owns, keyed by pid with its --type=
// flag. Backup path for when the browser-level CDP session is itself
// wedged and SystemInfo can't be asked.
function scanChromiumPids(): Map<number, string> {
  const pids = new Map<number, string>();
  let entries: string[] = [];
  try {
    entries = fs.readdirSync('/proc');
  } catch {
    return pids;
  }
  for (const ent of entries) {
    if (!/^\d+$/.test(ent)) continue;
    const cmdline = readOr(`/proc/${ent}/cmdline`).split('\0');
    const exe = cmdline[0] ?? '';
    if (!/chrom(e|ium)/i.test(exe)) continue;
    const typeArg = cmdline.find((a) => a.startsWith('--type='));
    pids.set(Number(ent), typeArg ? typeArg.slice(7) : 'browser');
  }
  return pids;
}

export interface PageBuffers {
  console: string[];
  errors: string[];
  crashed: boolean;
}

export function attachBuffers(page: Page): PageBuffers {
  const buffers: PageBuffers = { console: [], errors: [], crashed: false };
  const push = (arr: string[], line: string) => {
    arr.push(`${new Date().toISOString()} ${line.slice(0, 600)}`);
    if (arr.length > 500) arr.shift();
  };
  page.on('console', (msg) => push(buffers.console, `[${msg.type()}] ${msg.text()}`));
  page.on('pageerror', (err) => push(buffers.errors, `pageerror: ${err.message}`));
  page.on('crash', () => {
    buffers.crashed = true;
    push(buffers.errors, 'page crashed');
  });
  return buffers;
}

export async function captureHangEvidence(page: Page, testInfo: TestInfo, buffers: PageBuffers) {
  const evidence: Record<string, unknown> = {
    test: testInfo.titlePath.join(' › '),
    status: testInfo.status,
    wallClock: new Date().toISOString(),
    pageClosed: page.isClosed(),
    pageCrashed: buffers.crashed,
    url: page.url(),
  };

  if (!page.isClosed()) {
    // Who still answers: the page main thread, the CDP transport
    // itself, the compositor, and each dedicated worker (skwasm's
    // rasterizer lives in one). The pattern of which of these stall is
    // the fingerprint of where the hang sits.
    evidence.mainThread = await race(
      page.evaluate(
        `({ now: performance.now(), lastRaf: window.__wax_lastRaf, rafCount: window.__wax_rafCount,
            sinceRafMs: performance.now() - (window.__wax_lastRaf ?? 0),
            vis: document.visibilityState, err: window.__wax_lastError, rej: window.__wax_lastRejection })`,
      ),
      4000,
    );

    const cdp = await race(page.context().newCDPSession(page), 3000);
    if (cdp.ok) {
      const session = cdp.value as import('playwright-core').CDPSession;
      evidence.cdpEvaluate = await race(
        session.send('Runtime.evaluate', { expression: '1', timeout: 2000 } as never),
        4000,
      );
      const shot = await race(session.send('Page.captureScreenshot'), 6000);
      evidence.compositorScreenshot = shot.ok
        ? { ok: true, ms: shot.ms, bytes: (shot.value as { data: string }).data.length }
        : shot;
      if (shot.ok) {
        const png = Buffer.from((shot.value as { data: string }).data, 'base64');
        fs.writeFileSync(testInfo.outputPath('hang-compositor.png'), png);
      }
    } else {
      evidence.cdpSession = cdp;
    }

    evidence.workers = await Promise.all(
      page.workers().map(async (worker) => ({
        url: worker.url().slice(-120),
        probe: await race(worker.evaluate('({ now: performance.now() })'), 3000),
      })),
    );
  }

  // OS-level truth, taken twice to expose per-thread cpu movement.
  const browser = page.context().browser();
  let pids = new Map<number, string>();
  if (browser) {
    const bcdp = await race(browser.newBrowserCDPSession(), 3000);
    if (bcdp.ok) {
      const session = bcdp.value as import('playwright-core').CDPSession;
      const info = await race(session.send('SystemInfo.getProcessInfo'), 3000);
      if (info.ok) {
        for (const p of (info.value as { processInfo: { type: string; id: number }[] }).processInfo) {
          pids.set(p.id, p.type);
        }
      }
      await session.detach().catch(() => {});
    }
  }
  evidence.pidSource = pids.size > 0 ? 'SystemInfo' : 'procScan';
  if (pids.size === 0) pids = scanChromiumPids();

  const first = snapshotPids(pids);
  await new Promise((resolve) => setTimeout(resolve, 1200));
  const second = snapshotPids(pids);
  const byTid = new Map<number, ThreadSnap>();
  for (const proc of first) for (const t of proc.threads) byTid.set(t.tid, t);
  evidence.processes = second.map((proc) => ({
    pid: proc.pid,
    type: proc.type,
    threads: proc.threads.map((t) => ({
      tid: t.tid,
      comm: t.comm,
      state: t.state,
      wchan: t.wchan,
      cpuDeltaTicks: t.cpuTicks - (byTid.get(t.tid)?.cpuTicks ?? t.cpuTicks),
    })),
  }));

  evidence.console = buffers.console.slice(-120);
  evidence.pageErrors = buffers.errors.slice(-40);

  const out = testInfo.outputPath('hang-evidence.json');
  fs.writeFileSync(out, JSON.stringify(evidence, null, 2));
  await testInfo.attach('hang-evidence', { path: out, contentType: 'application/json' });

  // The one-line verdict, greppable from a suite log.
  const main = evidence.mainThread as ProbeResult | undefined;
  const workers = (evidence.workers as { probe: ProbeResult }[] | undefined) ?? [];
  const summary = [
    `hangprobe: main=${main ? (main.ok ? `ok(${main.ms}ms)` : `STALLED(${main.err})`) : 'closed'}`,
    `workers=${workers.map((w) => (w.probe.ok ? 'ok' : 'STALLED')).join(',') || 'none'}`,
    `crashed=${buffers.crashed}`,
  ].join(' ');
  console.log(`[${path.basename(testInfo.outputDir)}] ${summary}`);
}
