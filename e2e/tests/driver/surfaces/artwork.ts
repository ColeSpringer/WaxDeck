// The artwork manager: the slot grid on the metadata editor, and setting
// a cover from a file the way a person does. And the other end of a
// cover write: what a page that was only looking is owed when the cover
// changes somewhere else.

import { Locator, Request, WebSocketRoute, expect } from '@playwright/test';
import { SemanticsIds, sem } from '../../semantics-ids';
import { Surface } from '../context';
import { T } from '../budgets';
import { wheelIntoReach } from '../gestures';

/// The client's catalog window (`kCatalogRefreshWindow`): the least gap
/// between two of its refresh passes, and what it counts a busy stretch
/// of changes in. A test on the app's side reads this line and holds the
/// two together.
const catalogWindow = 5_000;

/// How long a page is given to ask for a changed cover again, from the
/// client's rule. Named in a window that stays small, a cover on screen
/// is dropped and asked for again as the frame is heard. Inside a
/// stretch too busy to follow by name it is asked for with every other
/// cover on screen when the stretch ends: the window that ran over, then
/// the one after it. Either way on the tier a condition the client
/// reaches on its own gets.
const afresh = 2 * catalogWindow + T.assert;

/// The page's event socket, in the test's hand.
export interface LiveSocket {
  /// The page has said its first frame, its subscribe, which is what
  /// makes it a client the server tells about a change. A change made
  /// before that reaches the page as a catch-up that names nothing.
  subscribed(): Promise<void>;

  /// A stretch of catalog changes too busy to follow by name, said to
  /// the page as the server would say it: two invalidations that between
  /// them name more entities than one carries.
  ///
  /// Said on the socket and not made through the API: the fixture
  /// catalog holds fewer entities than that, and each is a row some spec
  /// reads. The names are nobody's, so nothing is refetched for them.
  /// Answers the instant it was said.
  busy(): number;

  /// The server has said, on this socket, that the catalog entity `pid`
  /// changed: a catalog invalidation naming it, live or in answer to the
  /// subscribe.
  named(pid: string): Promise<void>;
}

export class Artwork extends Surface {
  /// The metadata editor's own location for one item, which is where the
  /// slot grid lives. A deep link the app itself mints.
  editorLocation(pid: string): string {
    return `/metadata/${pid}`;
  }

  /// One slot's tile. Its accessible name is what it holds - the format
  /// and pixel size the catalog stored - so a spec asserts that rather
  /// than reading it out of a control.
  slot(role: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.artSlot(role)));
  }

  /// The control that opens the file chooser for one slot.
  setSlot(role: string): Locator {
    return this.ctx.page.locator(sem(SemanticsIds.artSlotSet(role)));
  }

  /// What a tile says it holds, by accessible name. A slot draws as one
  /// image with a spoken description rather than as text nodes.
  slotNamed(name: RegExp): Locator {
    return this.ctx.page.getByRole('img', { name });
  }

  /// Set a slot's cover through the real chooser.
  ///
  /// The chooser event is armed before the click that opens it, for the
  /// reason the uploads surface gives: a native dialog is not a page
  /// element and there is no second chance once it has opened.
  async setCoverFromFile(role: string, file: string): Promise<void> {
    const page = this.ctx.page;
    const control = this.setSlot(role);
    await control.waitFor({ timeout: T.nav });
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser'),
      control.click({ force: true }),
    ]);
    await chooser.setFiles([file]);
  }

  /// Bring a row into the window, so the cover it draws is one the page
  /// holds.
  async intoView(row: Locator): Promise<void> {
    await wheelIntoReach(this.ctx.page, row);
  }

  /// The page's event socket through a route the handle holds. Asked for
  /// before the page loads: the socket opens during boot. A routed socket
  /// is still the browser's own, and what the server says on it reaches
  /// the page untouched.
  async liveSocket(): Promise<LiveSocket> {
    let socket: WebSocketRoute | undefined;
    let spoke = false;
    const heard: string[] = [];
    await this.ctx.page.routeWebSocket(
      (url) => url.pathname === '/api/v1/ws',
      (ws) => {
        socket = ws;
        spoke = false;
        const server = ws.connectToServer();
        ws.onMessage((message) => {
          spoke = true;
          server.send(message);
        });
        server.onMessage((message) => {
          if (typeof message === 'string') heard.push(message);
          ws.send(message);
        });
      },
    );
    const naming = (frame: string, pid: string) => {
      try {
        const f = JSON.parse(frame);
        return f.type === 'invalidate' && f.topic === 'catalog' && Array.isArray(f.pids) && f.pids.includes(pid);
      } catch {
        return false;
      }
    };
    const names = (from: number) =>
      Array.from({ length: 40 }, (_, i) => `al-${String(from + i).padStart(26, '0')}`);
    return {
      subscribed: () => expect.poll(() => spoke, { timeout: T.nav }).toBe(true),
      busy: () => {
        if (socket === undefined) throw new Error('the page has opened no event socket');
        const said = Date.now();
        for (const from of [0, 40]) {
          socket.send(JSON.stringify({ type: 'invalidate', topic: 'catalog', pids: names(from) }));
        }
        return said;
      },
      named: (pid) =>
        expect
          .poll(() => heard.some((frame) => naming(frame, pid)), { timeout: T.nav })
          .toBe(true),
    };
  }

  /// The page asking for one entity's cover again under the tag of a
  /// replacement (`v`): how a cover changed anywhere reaches a page that
  /// is already drawing it. Armed before the change, awaited after it.
  ///
  /// The request and not the canvas, which looks the same for a cover
  /// fetched again and one never dropped; and the tag, because without
  /// it the browser answers from the copy it has kept for the day.
  ///
  /// The client gets there by one of two paths, by name or at the end
  /// of a busy stretch, and both end in this same request; the budget
  /// is the longer path's (see `afresh`). Answers the instant the page
  /// asked.
  askedAfresh(pid: string): Promise<number> {
    const path = `/api/v1/items/${pid}/art`;
    const asked = this.ctx.page
      .waitForRequest(
        (request: Request) => {
          const url = new URL(request.url());
          return url.pathname === path && /^\d+$/.test(url.searchParams.get('v') ?? '');
        },
        { timeout: afresh },
      )
      .then(() => Date.now());
    // Held by the caller across the write; a write that fails first must
    // not leave this to reject unheard.
    asked.catch(() => {});
    return asked;
  }

  /// The page asking for one entity's cover under a tag newer than
  /// `after`, and answered: the tag and the bytes it was given. A tag
  /// from before (a replacement the page remembers) is not this; the
  /// budget lets a page boot first.
  coverAskedAfter(pid: string, after: number): Promise<{ tag: number; body: Buffer }> {
    const path = `/api/v1/items/${pid}/art`;
    const tagOf = (url: URL) => {
      const v = url.searchParams.get('v') ?? '';
      return /^\d+$/.test(v) ? Number(v) : -1;
    };
    const answered = this.ctx.page
      .waitForResponse(
        (response) => {
          const url = new URL(response.url());
          return url.pathname === path && tagOf(url) > after && response.status() === 200;
        },
        { timeout: T.nav + afresh },
      )
      .then(async (response) => ({ tag: tagOf(new URL(response.url())), body: await response.body() }));
    // Held by the caller across the write, as askedAfresh is.
    answered.catch(() => {});
    return answered;
  }

  /// Closes the page as a visitor closes the tab: the browser context,
  /// and what the page kept in its storage, stay.
  async leave(): Promise<void> {
    await this.ctx.page.close();
  }

  /// A cover changed inside a busy stretch was asked for when the
  /// stretch ended and not by name: the window that heard the stretch
  /// `said` has to end and a whole one follow, so the page cannot have
  /// `asked` sooner than one window on, whatever else the catalog is
  /// doing. Told by name it asks at the next paced pass, sooner.
  ///
  /// One thing trips this falsely: a stretch of somebody else's making
  /// that ended in the moment before this one was said, whose own ask
  /// for every cover is then the request that was seen.
  askedAtStretchEnd(said: number, asked: number): void {
    expect(
      asked - said,
      'the cover was asked for before the busy stretch could have ended',
    ).toBeGreaterThanOrEqual(catalogWindow);
  }
}
