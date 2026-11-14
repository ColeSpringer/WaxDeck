import { Page } from '@playwright/test';

// Frame pacing while a surface is scrolled, as one reusable measurement.
//
// Extracted from the library-grid scenario so the index and bucket
// surfaces can be measured the same way and their numbers compared with
// it. Any spec importing this must be excluded from the hangprobe
// heartbeat (see fixtures.ts): the collector below is a
// self-rescheduling rAF loop, which defeats idle throttling and adds a
// callback to every frame whose pacing the measurement exists to report.

export interface ScrollPacing {
  /// Frames collected, after the warm-up is discarded.
  frames: number;
  meanMs: number;
  fps: number;
  /// Diagnostic, not gated. The pre-agreed budgets are mean frame rate
  /// and long-frame share; p95 is reported because it is what tells a
  /// slow average apart from a smooth run with a few stalls in it, and
  /// adding a budget for it would be inventing a gate criterion nobody
  /// agreed to.
  p95Ms: number;
  /// Share of frames longer than 50ms - a visible hitch, not a slow
  /// average.
  longFrameShare: number;
}

export interface ScrollPacingOptions {
  /// Wheel events to send. The default paces a long enough scroll to
  /// carry a virtualized list through several load-more rounds.
  steps?: number;
  /// Pixels per wheel event.
  deltaY?: number;
  /// Pause between wheel events, which is what makes the scroll
  /// human-paced rather than a single jump.
  stepPauseMs?: number;
}

interface Collector {
  __frames: number[];
  __stop: boolean;
  /// Which run owns the page. A loop only exits by checking `__stop`
  /// after it has already pushed a frame, so a start landing within a
  /// frame of a stop would leave the old loop alive to reschedule itself
  /// into the new run - two loops pushing into one array, halving the
  /// apparent deltas and doubling the reported frame rate. Claiming a
  /// run number makes that structural rather than a matter of how far
  /// apart two measurements happen to fall.
  __run: number;
}

// The collector, installed and read back through two evaluates. Frame
// deltas are collected in the page rather than sampled from the driver:
// a screenshot-based sample would measure the driver, not the compositor.
const START_COLLECTOR = () => {
  const w = window as unknown as Collector;
  const run = (w.__run = (w.__run ?? 0) + 1);
  w.__frames = [];
  w.__stop = false;
  let last = performance.now();
  const tick = (now: number) => {
    if (w.__run !== run) return;
    w.__frames.push(now - last);
    last = now;
    if (!w.__stop) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
};

// Frames discarded from the head of the sample, spanning the gap between
// installing the collector and the first wheel event.
const WARMUP_FRAMES = 5;

const STOP_COLLECTOR = () => {
  const w = window as unknown as Collector;
  w.__stop = true;
  return w.__frames;
};

// Wheels through whatever is under the pointer and reports how the
// frames paced. The caller navigates and waits for the surface first;
// this only measures.
export async function measureScrollPacing(
  page: Page,
  options: ScrollPacingOptions = {},
): Promise<ScrollPacing> {
  const { steps = 120, deltaY = 600, stepPauseMs = 100 } = options;

  await page.evaluate(START_COLLECTOR);
  // A context created without an explicit viewport reports none, and the
  // window is the viewport then; asking the page is right either way and
  // beats inventing a number the pointer would land outside of.
  const viewport =
    page.viewportSize() ??
    (await page.evaluate(() => ({ width: innerWidth, height: innerHeight })));
  await page.mouse.move(viewport.width / 2, viewport.height / 2);
  for (let i = 0; i < steps; i++) {
    await page.mouse.wheel(0, deltaY);
    await page.waitForTimeout(stepPauseMs);
  }
  const frames: number[] = await page.evaluate(STOP_COLLECTOR);

  // The first few frames span the gap between installing the collector
  // and the scroll starting, which is idle time and not pacing.
  const settled = frames.slice(WARMUP_FRAMES);
  if (settled.length === 0) {
    // Deliberately an error and not a zeroed result. A page that drew
    // almost nothing across a scroll lasting seconds is the renderer
    // hang this suite has a whole probe for, and it has to fail saying
    // so: zeroes would divide to a NaN long-frame share and an *infinite*
    // frame rate, which passes the budget it just catastrophically
    // missed.
    throw new Error(
      `scroll pacing collected ${frames.length} frames over ` +
        `${steps} steps (${(steps * stepPauseMs) / 1000}s) - the page ` +
        `rendered nothing to measure`,
    );
  }
  const meanMs = settled.reduce((a, b) => a + b, 0) / settled.length;
  const sorted = [...settled].sort((a, b) => a - b);
  return {
    frames: settled.length,
    meanMs,
    fps: 1000 / meanMs,
    p95Ms: sorted[Math.floor(sorted.length * 0.95)],
    longFrameShare: settled.filter((f) => f > 50).length / settled.length,
  };
}

// One line per measured surface, in the shape the gate has always
// printed. Measured values are recorded whether or not the budget held:
// a run that only says "failed" cannot be compared with the last one.
export function reportScrollPacing(label: string, pacing: ScrollPacing) {
  console.log(
    `  ${label.padEnd(15)} mean ${pacing.meanMs.toFixed(1)}ms (${pacing.fps.toFixed(0)}fps), ` +
      `p95 ${pacing.p95Ms.toFixed(1)}ms, >50ms share ${(pacing.longFrameShare * 100).toFixed(1)}%`,
  );
}

// Frame pacing across a theme switch, beside the scroll measurement.
//
// A theme change is a burst of work and then stillness, so the question is
// how the frames inside the burst are spaced: a switch that rebuilds the
// whole tree every frame for a fade shows up as long intervals, and one that
// lands in a single frame as a single long one. The window starts just
// before the change is made, so it includes the gesture that makes it.

export interface ThemeSwitchPacing {
  /// Frames drawn inside the window.
  frames: number;
  medianMs: number;
  /// The longest gap between two frames inside the window.
  worstMs: number;
}

export interface ThemeSwitchOptions {
  windowMs?: number;
}

interface StampCollector {
  __stamps: number[];
  __stampsStop: boolean;
  __stampsRun: number;
}

// Absolute frame times rather than deltas, so the window can be cut out
// afterwards. Own globals and run counter: this must not share state with
// the scroll collector above.
const START_STAMPS = () => {
  const w = window as unknown as StampCollector;
  const run = (w.__stampsRun = (w.__stampsRun ?? 0) + 1);
  w.__stamps = [];
  w.__stampsStop = false;
  const tick = (now: number) => {
    if (w.__stampsRun !== run) return;
    w.__stamps.push(now);
    if (!w.__stampsStop) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
  return performance.now();
};

const STOP_STAMPS = () => {
  const w = window as unknown as StampCollector;
  w.__stampsStop = true;
  return w.__stamps;
};

// Runs [change] - the one action that switches the theme - and reports how
// the frames paced for [windowMs] from just before it. The caller has the
// surface up and any menu open already, so only the switch is measured.
export async function measureThemeSwitchPacing(
  page: Page,
  change: () => Promise<void>,
  options: ThemeSwitchOptions = {},
): Promise<ThemeSwitchPacing> {
  const { windowMs = 400 } = options;

  const start: number = await page.evaluate(START_STAMPS);
  const startedAt = Date.now();
  await change();
  const remaining = windowMs - (Date.now() - startedAt);
  if (remaining > 0) await page.waitForTimeout(remaining);
  const stamps: number[] = await page.evaluate(STOP_STAMPS);

  // Each frame's interval is the gap from the one before it, which may
  // itself fall before the window.
  const intervals: number[] = [];
  for (let i = 1; i < stamps.length; i++) {
    if (stamps[i] >= start && stamps[i] <= start + windowMs) {
      intervals.push(stamps[i] - stamps[i - 1]);
    }
  }
  if (intervals.length === 0) {
    throw new Error(
      `theme switch pacing collected no frames in ${windowMs}ms - the page ` +
        `rendered nothing to measure`,
    );
  }
  const sorted = [...intervals].sort((a, b) => a - b);
  return {
    frames: intervals.length,
    medianMs: sorted[Math.floor(sorted.length / 2)],
    worstMs: sorted[sorted.length - 1],
  };
}

export function reportThemeSwitchPacing(label: string, pacing: ThemeSwitchPacing) {
  console.log(
    `  ${label.padEnd(22)} ${pacing.frames} frames, median ${pacing.medianMs.toFixed(1)}ms, ` +
      `worst ${pacing.worstMs.toFixed(1)}ms`,
  );
}
