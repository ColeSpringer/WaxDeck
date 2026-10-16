// Listing pages the way the contract allows them to come back: short, even
// empty, and still carrying a cursor (api/spec/library.yaml). The server
// that once answered them so - it cut a page before dropping the rows the
// caller may not see - now scopes first, so a client's duty to read on
// past one has to be met with a page shaped here.

import { Page } from '@playwright/test';

/// Answers the first page of every listing read `reads` takes - the page
/// it asks for without a cursor - with no rows and the cursor the server
/// gave it. Every later page goes to the server untouched, and so does a
/// first page that carried no cursor: emptied, that one would say the
/// listing is empty, which is another claim.
export async function emptyFirstPages(page: Page, reads: (url: URL) => boolean): Promise<void> {
  await page.route(
    (url) => reads(url) && !url.searchParams.has('cursor'),
    async (route) => {
      const response = await route.fetch();
      const body = response.ok() ? ((await response.json()) as { nextCursor?: string }) : {};
      if (!response.ok() || !body.nextCursor) {
        await route.fulfill({ response });
        return;
      }
      await route.fulfill({ response, json: { ...body, items: [] } });
    },
  );
}
