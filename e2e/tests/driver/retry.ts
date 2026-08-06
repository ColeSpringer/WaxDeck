// Retry around the file-mutation lease.
//
// One installation, four workers: a delete, an upload, a rescan and an
// unfetch all take the same catalog lease, and a spec that wants it
// while a sibling holds it is refused with `catalog-busy`. That refusal
// clears on its own and is nothing to do with the code under test - any
// other refusal is, and is rethrown with the server's own message.
//
// The budget is the fetch tier, not the assert tier: what is being
// waited on is another worker's upload, rescan or delete finishing,
// which is server-side work off the request and exactly what that tier
// names. It costs nothing on the failure path either - a refusal that is
// not `catalog-busy` is rethrown on the first attempt rather than
// waiting the budget out.
//
// Its own file rather than driver/index.ts, so the seed layer can use it
// without importing the module that constructs the whole App.

import { expect } from '@playwright/test';
import { T } from './budgets';

/// `transient` names the refusals worth waiting out. `catalog-busy` by
/// default, which is always somebody else's file mutation finishing.
///
/// A caller setting up a PRECONDITION may add to that. Removing an
/// episode's file is refused with `conflict` while anyone is listening
/// to it - the file is one catalog row shared by every subscriber - and
/// for a test whose subject is that refusal, waiting it out would be
/// waiting out the assertion. For a test that merely needs the episode
/// unfetched before it starts, it is another sibling finishing, no
/// different from the lease.
export async function retryCatalogBusy<T2>(
  attempt: () => Promise<T2>,
  options: { what?: string; within?: number; transient?: readonly string[] } = {},
): Promise<T2> {
  const {
    what = 'the catalog lease should free',
    within = T.fetch,
    transient = ['catalog-busy'],
  } = options;
  let result: T2;
  let last: unknown;
  await expect
    .poll(
      async () => {
        try {
          result = await attempt();
          return true;
        } catch (e) {
          last = e;
          if (transient.some((code) => isCode(e, code))) return false;
          throw e;
        }
      },
      { timeout: within, message: what },
    )
    // Rethrows the last refusal rather than reporting "expected true,
    // received false". A poll that gives up on a transient code has the
    // server's own message in hand, and a report that drops it sends the
    // reader to the wrong layer entirely.
    .toBe(true)
    .catch(() => {
      throw new Error(`${what}; last refusal was: ${String(last)}`);
    });
  return result!;
}

/// Whether a refusal really carries this error code.
///
/// Matched against the structured `{code, message}` the server sends,
/// not against the whole stringified error. `Api.json` builds that
/// string as `METHOD /path answered NNN: {body}`, so a plain substring
/// test retries anything whose *message* happens to contain the word -
/// an `invalid-request` reading "conflicts with an existing station"
/// would be waited out for the full budget and then reported as a lease
/// that never freed, with the real error nowhere in the run.
function isCode(error: unknown, code: string): boolean {
  const text = String(error);
  const body = text.slice(text.indexOf('{'));
  try {
    return (JSON.parse(body) as { code?: string }).code === code;
  } catch {
    return false;
  }
}
