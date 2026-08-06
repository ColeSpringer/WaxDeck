// Every wait in the suite, named by what it is waiting for.
//
// The specs used to carry their own numbers - 230 of them, chosen one
// incident at a time, so `timeout: 15_000` beside a fetch and
// `timeout: 15_000` beside a click meant two unrelated things that
// happened to agree. A named tier says which kind of wait it is, and
// tuning a kind is one edit here rather than a grep. Specs pass no
// numbers at all; a driver method that needs an unusual budget takes
// `{ within: T.fetch }`.
//
// The values are what the suite had already converged on, not new
// guesses.
export const T = {
  /// One interaction settling: a menu row coming to rest, a field taking
  /// a keystroke, a control appearing on a screen that is already up.
  step: 5_000,

  /// A control being driven to completion, retries included. The unit
  /// the gesture primitives budget themselves against.
  action: 20_000,

  /// Arriving somewhere: a route transition, a cold load, the app
  /// booting far enough to draw the shell.
  nav: 30_000,

  /// A condition the client reaches on its own - a poll against the
  /// server, a value propagating into the UI.
  assert: 15_000,

  /// The live channel, as a promise rather than a kind of wait: an edit
  /// made elsewhere reaching an open client over the invalidation
  /// socket. Deliberately tighter than `step`, because the whole claim
  /// is that it arrives on the socket and not on whatever poll would
  /// eventually notice - a budget loose enough for the fallback is a
  /// budget that passes while the subject is broken.
  live: 3_000,

  /// Work the server does off the request: a download landing, a scan
  /// picking a file up, a worker draining a queue.
  fetch: 60_000,

  /// Media analysis. The streaming sidecar decodes real audio for these,
  /// and there is no faster answer to wait for.
  analyze: 90_000,
} as const;

/// Whole-test budgets, for the few scenarios that legitimately outlast
/// the config's 120s default. A test that needs one says so with
/// `test.setTimeout(J.long)` and the name explains why it is allowed.
export const J = {
  /// A scenario that waits on one piece of server-side media work.
  long: 180_000,

  /// An end-to-end journey whose steps each consume the last one's
  /// output - the shape the journey rule permits to stay whole.
  journey: 240_000,
} as const;

export type Budget = (typeof T)[keyof typeof T];
