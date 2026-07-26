// Hammer driver: opens N copies of the repro app and watches for the
// two signatures captured in the e2e evidence — a wasm RuntimeError
// (pageerror) or a full main-thread stall — then snapshots every
// chromium thread twice to show who is spinning. Set ST=1 to force
// single-threaded skwasm (the negative control: same workload, no
// render worker, no fault). Usage:
//   node drive.js [url] [pages] [minutes]
const { createRequire } = require('node:module');
const fs = require('node:fs');
const path = require('node:path');
const req = createRequire(path.resolve(__dirname, '..', 'package.json'));
const { chromium } = req('playwright-core');

const url = process.argv[2] || 'http://127.0.0.1:4499/';
const nPages = Number(process.argv[3] || 3);
const maxMinutes = Number(process.argv[4] || 30);
const outDir = `${__dirname}/evidence-${Date.now()}`;

const HEARTBEAT = `(() => {
  let n = 0;
  const loop = (t) => { window.__lastRaf = t; window.__rafCount = ++n; requestAnimationFrame(loop); };
  requestAnimationFrame(loop);
})();`;

function readOr(f) {
  try { return fs.readFileSync(f, 'utf8'); } catch { return ''; }
}

function snapshotChromium() {
  const procs = [];
  for (const ent of fs.readdirSync('/proc')) {
    if (!/^\d+$/.test(ent)) continue;
    const cmdline = readOr(`/proc/${ent}/cmdline`).split('\0');
    if (!/chrom(e|ium)/i.test(cmdline[0] || '')) continue;
    const typeArg = cmdline.find((a) => a.startsWith('--type='));
    const threads = [];
    for (const tid of (() => { try { return fs.readdirSync(`/proc/${ent}/task`); } catch { return []; } })()) {
      const stat = readOr(`/proc/${ent}/task/${tid}/stat`);
      const close = stat.lastIndexOf(')');
      if (close < 0) continue;
      const rest = stat.slice(close + 2).split(' ');
      threads.push({
        tid: Number(tid),
        comm: stat.slice(stat.indexOf('(') + 1, close),
        state: rest[0],
        wchan: readOr(`/proc/${ent}/task/${tid}/wchan`).trim() || '-',
        cpu: Number(rest[11] || 0) + Number(rest[12] || 0),
      });
    }
    procs.push({ pid: Number(ent), type: typeArg ? typeArg.slice(7) : 'browser', threads });
  }
  return procs;
}

async function dumpThreads(label) {
  const a = snapshotChromium();
  await new Promise((r) => setTimeout(r, 1200));
  const b = snapshotChromium();
  const cpuA = new Map();
  for (const p of a) for (const t of p.threads) cpuA.set(t.tid, t.cpu);
  const report = b.map((p) => ({
    pid: p.pid, type: p.type,
    hot: p.threads
      .map((t) => ({ ...t, delta: t.cpu - (cpuA.get(t.tid) ?? t.cpu) }))
      .filter((t) => t.delta > 0 || t.state === 'R'),
  })).filter((p) => p.hot.length > 0);
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(`${outDir}/${label}-threads.json`, JSON.stringify(report, null, 1));
  console.log(`[${label}] hot threads:`);
  for (const p of report) {
    for (const t of p.hot) {
      console.log(`  pid=${p.pid}(${p.type}) tid=${t.tid} ${t.comm} state=${t.state} wchan=${t.wchan} delta=${t.delta}`);
    }
  }
}

(async () => {
  const browser = await chromium.launch({ channel: 'chromium' });
  const started = Date.now();
  let done = false;

  const finish = async (why) => {
    if (done) return;
    done = true;
    console.log(`=== EVENT after ${((Date.now() - started) / 1000).toFixed(0)}s: ${why}`);
    await dumpThreads('event');
    await browser.close().catch(() => {});
    process.exit(0);
  };

  const pages = [];
  for (let i = 0; i < nPages; i++) {
    const page = await browser.newPage();
    await page.addInitScript(HEARTBEAT);
    if (process.env.ST === '1') {
      await page.route('**/flutter_bootstrap.js', async (route) => {
        const resp = await route.fetch();
        const body = (await resp.text()).replace(
          '_flutter.loader.load({',
          '_flutter.loader.load({config:{forceSingleThreadedSkwasm:true},',
        );
        await route.fulfill({ response: resp, body });
      });
    }
    page.on('pageerror', (e) => {
      const msg = String(e.message);
      fs.mkdirSync(outDir, { recursive: true });
      fs.appendFileSync(`${outDir}/pageerrors.log`,
        `${new Date().toISOString()} page${i} ${msg}\n${e.stack || ''}\n\n`);
      console.log(`page${i} pageerror: ${msg.slice(0, 120)}`);
      if (/memory access out of bounds|RuntimeError|unreachable/i.test(msg)) {
        finish(`wasm trap on page${i}: ${msg.slice(0, 120)}`);
      }
    });
    page.on('crash', () => finish(`page${i} crashed`));
    await page.goto(url, { waitUntil: 'load' });
    pages.push(page);
  }
  console.log(`driving ${nPages} pages at ${url}`);

  const misses = new Array(nPages).fill(0);
  const lastCount = new Array(nPages).fill(0);
  while (!done) {
    if (Date.now() - started > maxMinutes * 60_000) {
      console.log('=== time cap reached, no event');
      await browser.close().catch(() => {});
      process.exit(1);
    }
    await new Promise((r) => setTimeout(r, 2000));
    for (let i = 0; i < nPages; i++) {
      if (done) break;
      const res = await Promise.race([
        pages[i].evaluate('window.__rafCount').then((v) => ({ ok: true, v }), (e) => ({ ok: false, e: String(e) })),
        new Promise((r) => setTimeout(() => r({ ok: false, e: 'probe timeout' }), 4000)),
      ]);
      if (res.ok) {
        misses[i] = 0;
        lastCount[i] = res.v;
      } else if (!String(res.e).includes('navigat')) {
        misses[i]++;
        console.log(`page${i} probe miss ${misses[i]} (${String(res.e).slice(0, 60)}) rafCount was ${lastCount[i]}`);
        if (misses[i] >= 3) await finish(`page${i} main thread stalled`);
      }
    }
    const mins = ((Date.now() - started) / 60000).toFixed(1);
    if (Math.floor(Date.now() / 30000) !== Math.floor((Date.now() - 2100) / 30000)) {
      console.log(`t=${mins}m rafCounts=${lastCount.join(',')}`);
    }
  }
})();
