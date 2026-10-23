// Libraries a test creates on the shared server, taken out again whatever
// the test did: one left behind is walked by every later scan, and keeps
// its name from an attempt that runs again.

import { expect } from '@playwright/test';
import { Api } from './api';
import { T } from './budgets';
import { retryCatalogBusy } from './retry';

/// Takes out a library a test made, unless it is gone already: the test's
/// own removal may have taken it, or be taking it now, whose lease the
/// call waits out.
export async function removeLibraryIfThere(api: Api, pid: string): Promise<void> {
  await retryCatalogBusy(
    async () => {
      const resp = await api.raw.delete('/libraries/{pid}', { path: { pid } });
      if (resp.status() === 202 || resp.status() === 404) return;
      throw new Error(`DELETE /libraries/${pid} answered ${resp.status()}: ${await resp.text()}`);
    },
    { what: 'the library the test made should go' },
  );
}

/// Takes out every library named `name` an earlier attempt left, and waits
/// until its name is free again: the removal's end has been followed up,
/// which its `library.remove` audit entry marks.
export async function removeLibrariesNamed(api: Api, name: string): Promise<void> {
  const listed = await api.get('/libraries');
  for (const lib of listed.libraries.filter((l) => l.name === name)) {
    await removeLibraryIfThere(api, lib.pid);
    await expect
      .poll(
        async () => {
          const audit = await api.tryGet('/admin/audit', {
            query: { action: 'library.remove', limit: 50 },
          });
          return (audit?.events ?? []).some((e) => e.targetPid === lib.pid);
        },
        { timeout: T.fetch, message: 'the earlier attempt\'s library should be gone' },
      )
      .toBe(true);
  }
}
