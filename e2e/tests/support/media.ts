// The page's media traffic, seen and steered from outside the app.
//
// What the playback specs need to see sits below the widgets: which
// minted stream the player fetched, under which media token, which fetch
// the server (or this file) refused, and whether the element really moved
// afterwards. None of it is drawn. The element itself is no help to a
// selector either: just_audio plays through an `<audio>` it never attaches
// to the document, so an init script remembers every media element the
// page creates instead, and the span each one played of every source.
//
// What they need to steer is the stream: a refusal the server would give
// (a lapsed token, a streaming engine that is away) answered here
// instead, at the moment the spec chooses. Every fixture track is a few
// seconds long and arrives whole in one ranged response, so a stream
// that is still being fetched - the only kind a lapsed token can catch
// mid-listen - is made too: its first fetch is cut short, and the fetch
// the element comes back with for the rest is held until the spec
// answers it. And a stream the server encodes as it goes, which answers
// no ranges and is still arriving when a listener scrubs past it: a relay
// on this machine answers the first fetch that way, with a part of it.

import { createServer, ServerResponse } from 'node:http';
import { AddressInfo } from 'node:net';
import { Page, Request, Route } from '@playwright/test';

const STREAM = /\/media\/stream\?/;
const PLAY_INFO = /\/items\/([^/]+)\/play-info$/;

/// A URL's query parameter; a minted stream URL may come relative.
const param = (url: string, name: string) =>
  new URL(url, 'http://minted.invalid').searchParams.get(name) ?? '';

/// The media token a minted stream URL carries.
const mediaToken = (url: string) => param(url, 'mt');

const streamPid = (url: string) => param(url, 'pid');

/// Whether two URLs name one stream. Not by token alone: a cut is outside
/// the token, so a stream and a cut of it minted in one second share one.
const sameStream = (a: string, b: string) => {
  const [x, y] = [a, b].map((u) => new URL(u, 'http://minted.invalid'));
  return x.pathname === y.pathname && x.search === y.search;
};

/// A play-info request: the player minting a stream. `seq` orders it
/// against every other event this file records.
export interface Mint {
  readonly seq: number;
  readonly pid: string;
  /// The position the mint asked to begin at, when it asked: a cut of a
  /// stream that answers no ranges, or a book's part.
  readonly positionMs?: number;
  /// When the minted token lapses, once the answer has arrived.
  expiresAt?: string;
  /// When the answer arrived, on this machine's clock (the stack's own).
  answeredAt?: number;
  /// The minted stream URL, once answered.
  url?: string;
  /// Whether the minted stream answers ranges, once answered: an encode
  /// (a bitrate cap over the original, say) does not.
  seekable?: boolean;
  /// Where on the item the served audio begins, once answered: zero
  /// unless the server cut the stream.
  startOffsetMs?: number;
}

/// A fetch of a minted stream: the media element's own, or the player's
/// probe of a URL that failed, which is a plain fetch.
export interface StreamFetch {
  readonly seq: number;
  readonly pid: string;
  readonly url: string;
  readonly token: string;
  readonly by: 'element' | 'probe';
}

/// A stream fetch answered with an error status, whoever answered it.
export interface StreamRefusal {
  readonly seq: number;
  readonly pid: string;
  readonly token: string;
  readonly status: number;
}

/// A stream whose first fetch was cut short, with the fetch the element
/// came back with for the rest held open.
export interface HeldStream {
  /// The media token the cut-short fetch carried.
  readonly token: string;
  /// Answers the held fetch, and every later fetch carrying this token,
  /// with the given refusal.
  refuse(status: number, body: object): void;
}

/// The stretch of a source the media elements played, in seconds on the
/// source's own clock: the earliest and the furthest positions it was at
/// while playing.
export interface PlayedSpan {
  readonly from: number;
  readonly to: number;
}

/// What the page remembers about its media elements; see MEDIA_HOOK.
interface MediaRecord {
  played: Record<string, PlayedSpan>;
}

// Runs in the page before the app boots. Remembers every audio and video
// element the page creates, and the span each source played while the
// element was playing: a position read later may belong to an element the
// player has already emptied for the next track, and where a source began
// playing is what tells a resume from a start over.
const MEDIA_HOOK = () => {
  const w = window as unknown as { __waxMedia?: MediaRecord; __waxMediaElements?: HTMLMediaElement[] };
  if (w.__waxMedia !== undefined) return;
  const record: MediaRecord = { played: {} };
  const elements: HTMLMediaElement[] = [];
  w.__waxMedia = record;
  w.__waxMediaElements = elements;
  const create = Document.prototype.createElement;
  Document.prototype.createElement = function (
    this: Document,
    tag: string,
    options?: ElementCreationOptions,
  ) {
    const element = create.call(this, tag, options);
    if (/^(audio|video)$/i.test(tag)) {
      const media = element as HTMLMediaElement;
      elements.push(media);
      // `playing` too: it fires where playback begins, which the first
      // `timeupdate` can trail by a quarter of a second.
      const note = () => {
        const src = media.currentSrc || media.src;
        if (src === '' || media.paused) return;
        const at = media.currentTime;
        const span = record.played[src];
        record.played[src] =
          span === undefined
            ? { from: at, to: at }
            : { from: Math.min(span.from, at), to: Math.max(span.to, at) };
      };
      media.addEventListener('playing', note);
      media.addEventListener('timeupdate', note);
    }
    return element;
  } as typeof Document.prototype.createElement;
};

/// One media element's source and where it stands, read in the page.
interface Holding {
  readonly src: string;
  readonly at: number;
  /// The end of what it has buffered, in seconds; zero when nothing.
  readonly buffered: number;
}

type Rule = (route: Route) => Promise<boolean>;

export class MediaTraffic {
  private seq = 0;
  private readonly mintList: Mint[] = [];
  private readonly fetchList: StreamFetch[] = [];
  private readonly refusalList: StreamRefusal[] = [];
  private readonly rules: Rule[] = [];
  private routed = false;
  private relay?: Promise<string>;

  private constructor(private readonly page: Page) {}

  /// Starts watching. Call it before the app boots: the element hook is
  /// an init script, and one added later meets only the next page load.
  static async watch(page: Page): Promise<MediaTraffic> {
    const traffic = new MediaTraffic(page);
    await page.addInitScript(MEDIA_HOOK);
    const mints = new Map<Request, Mint>();
    page.on('request', (request) => {
      const url = request.url();
      const minted = PLAY_INFO.exec(new URL(url).pathname);
      if (minted !== null && request.method() === 'GET') {
        const asked = param(url, 'positionMs');
        const mint: Mint = {
          seq: traffic.next(),
          pid: decodeURIComponent(minted[1]),
          ...(asked === '' ? {} : { positionMs: Number(asked) }),
        };
        mints.set(request, mint);
        traffic.mintList.push(mint);
      } else if (STREAM.test(url)) {
        traffic.fetchList.push({
          seq: traffic.next(),
          pid: streamPid(url),
          url,
          token: mediaToken(url),
          by: request.resourceType() === 'media' ? 'element' : 'probe',
        });
      }
    });
    page.on('response', async (response) => {
      const request = response.request();
      const mint = mints.get(request);
      if (mint !== undefined) {
        mints.delete(request);
        mint.answeredAt = Date.now();
        if (!response.ok()) return;
        try {
          const info = (await response.json()) as {
            expiresAt?: string;
            url?: string;
            seekable?: boolean;
            startOffsetMs?: number;
          };
          mint.expiresAt = info.expiresAt;
          mint.seekable = info.seekable;
          mint.startOffsetMs = info.startOffsetMs ?? 0;
          mint.url = info.url;
        } catch {
          // A body that went away with its page says nothing here.
        }
      } else if (STREAM.test(response.url()) && response.status() >= 400) {
        traffic.refusalList.push({
          seq: traffic.next(),
          pid: streamPid(response.url()),
          token: mediaToken(response.url()),
          status: response.status(),
        });
      }
    });
    return traffic;
  }

  /// The position the next event will take: everything recorded from now
  /// on has a `seq` above it.
  mark(): number {
    return this.seq;
  }

  /// Every mint so far, oldest first; for one item when `pid` is given.
  mints(pid?: string): Mint[] {
    return this.mintList.filter((m) => pid === undefined || m.pid === pid);
  }

  /// Every stream fetch so far, oldest first; for one item when `pid` is
  /// given.
  fetches(pid?: string): StreamFetch[] {
    return this.fetchList.filter((f) => pid === undefined || f.pid === pid);
  }

  /// Every stream fetch answered with an error status so far.
  refusals(): StreamRefusal[] {
    return [...this.refusalList];
  }

  /// Answers every stream fetch for `pid` with this status and JSON body
  /// instead of the server, until the returned undo runs.
  async refuse(pid: string, status: number, body: object): Promise<() => void> {
    const rule: Rule = async (route) => {
      if (streamPid(route.request().url()) !== pid) return false;
      await answer(route, status, body);
      return true;
    };
    await this.steer(rule);
    return () => {
      const at = this.rules.indexOf(rule);
      if (at >= 0) this.rules.splice(at, 1);
    };
  }

  /// Makes `pid`'s next stream one still being fetched: its first fetch
  /// is answered with most of the file and no more, and the fetch the
  /// element comes back with for the rest is held open. A later stream of
  /// `pid`, under another token, goes to the server untouched.
  ///
  /// Answers a reader for the held stream, undefined until the element
  /// has come back for the rest; `refuse` on it answers the held fetch.
  async holdContinuation(pid: string): Promise<() => HeldStream | undefined> {
    let token = '';
    let refusal: { status: number; body: object } | undefined;
    const held: Route[] = [];
    let stream: HeldStream | undefined;
    const rule: Rule = async (route) => {
      const url = route.request().url();
      if (streamPid(url) !== pid) return false;
      if (token === '') {
        token = mediaToken(url);
        await cutShort(route);
        return true;
      }
      if (mediaToken(url) !== token) return false;
      if (refusal !== undefined) {
        await answer(route, refusal.status, refusal.body);
        return true;
      }
      held.push(route);
      stream ??= {
        token,
        refuse: (status, body) => {
          refusal = { status, body };
          for (const route of held.splice(0)) void answer(route, status, body);
        },
      };
      return true;
    };
    await this.steer(rule);
    return () => stream;
  }

  /// Makes `pid`'s next stream one still being encoded: answered the way
  /// a live encode is (no length, no ranges), with the first `share` of
  /// what the server serves and the rest held for as long as the page
  /// lives. Shaped here rather than by the server, which answers an encode
  /// it has finished before as a whole file with ranges. A later stream of
  /// `pid` goes to the server untouched.
  async holdEncode(pid: string, share: number): Promise<void> {
    const relay = await this.relayBase();
    let taken = false;
    await this.steer(async (route) => {
      const url = new URL(route.request().url());
      if (taken || streamPid(url.href) !== pid) return false;
      taken = true;
      await route.continue({ url: `${relay}/${share}${url.pathname}${url.search}` });
      return true;
    });
  }

  /// The furthest any media element got while playing a stream of `pid`,
  /// in seconds; zero when none has played.
  async furthest(pid: string): Promise<number> {
    return (await this.played(pid))?.to ?? 0;
  }

  /// The span the media elements played of `pid`'s streams, on each
  /// stream's own clock; of the stream at `url` alone when it is given
  /// (as minted, or as fetched). Undefined while none of them has played.
  async played(pid: string, url?: string): Promise<PlayedSpan | undefined> {
    const record = await this.page.evaluate(
      () => (window as unknown as { __waxMedia?: MediaRecord }).__waxMedia ?? { played: {} },
    );
    const spans = Object.entries(record.played)
      .filter(([src]) => streamPid(src) === pid && (url === undefined || sameStream(src, url)))
      .map(([, span]) => span);
    if (spans.length === 0) return undefined;
    return {
      from: Math.min(...spans.map((s) => s.from)),
      to: Math.max(...spans.map((s) => s.to)),
    };
  }

  /// Where the element holding a stream of `pid` stands now, in seconds;
  /// null when no element holds one.
  async position(pid: string): Promise<number | null> {
    return (await this.holding(pid))?.at ?? null;
  }

  /// How far the element holding a stream of `pid` has buffered it, in
  /// seconds on the stream's own clock; null when no element holds one.
  async buffered(pid: string): Promise<number | null> {
    return (await this.holding(pid))?.buffered ?? null;
  }

  /// The element holding a stream of `pid`, the newest when several do.
  private async holding(pid: string): Promise<Holding | undefined> {
    const all = await this.page.evaluate(() =>
      ((window as unknown as { __waxMediaElements?: HTMLMediaElement[] }).__waxMediaElements ?? [])
        .filter((e) => e.src !== '')
        .map((e) => ({
          src: e.src,
          at: e.currentTime,
          buffered: e.buffered.length === 0 ? 0 : e.buffered.end(e.buffered.length - 1),
        })),
    );
    return all.filter((h) => streamPid(h.src) === pid).at(-1);
  }

  private next(): number {
    return ++this.seq;
  }

  /// The relay [holdEncode] sends a stream through, started on first use
  /// and gone with the page: a fetch of `/<share>/<path>` is answered with
  /// that share of what the server answers for `<path>`, and held open.
  private relayBase(): Promise<string> {
    this.relay ??= (async () => {
      const origin = new URL(this.page.url()).origin;
      const held: ServerResponse[] = [];
      const server = createServer((req, res) => void relayed(origin, req.url ?? '/', res, held));
      await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
      this.page.once('close', () => {
        for (const res of held) res.destroy();
        server.close();
      });
      return `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
    })();
    return this.relay;
  }

  /// One route over every stream fetch, consulting the rules newest
  /// first; a fetch no rule takes goes to the server.
  private async steer(rule: Rule): Promise<void> {
    this.rules.unshift(rule);
    if (this.routed) return;
    this.routed = true;
    await this.page.route(STREAM, async (route) => {
      for (const each of [...this.rules]) {
        if (await each(route)) return;
      }
      await route.fallback();
    });
  }
}

/// One fetch through [MediaTraffic.holdEncode]'s relay: the server's
/// answer for the path after the share, as a live encode sends it, cut
/// to that share and left open. A refusal passes through whole.
async function relayed(
  origin: string,
  path: string,
  res: ServerResponse,
  held: ServerResponse[],
): Promise<void> {
  const [, share, ...rest] = path.split('/');
  try {
    const upstream = await fetch(`${origin}/${rest.join('/')}`);
    const body = Buffer.from(await upstream.arrayBuffer());
    const type = upstream.headers.get('content-type') ?? 'application/octet-stream';
    if (!upstream.ok) {
      res.writeHead(upstream.status, { 'content-type': type });
      res.end(body);
      return;
    }
    res.writeHead(200, { 'content-type': type, 'accept-ranges': 'none', 'cache-control': 'no-store' });
    res.write(body.subarray(0, Math.floor(body.length * Number(share))));
    held.push(res);
  } catch {
    // The page let the fetch go meanwhile, or went away itself.
    res.destroy();
  }
}

/// A refusal in the server's own envelope.
async function answer(route: Route, status: number, body: object): Promise<void> {
  try {
    await route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
  } catch {
    // The page gave up on this fetch meanwhile (a stop, a new source);
    // there is no one left to refuse.
  }
}

/// The first fetch of a stream, answered with 70% of the file as a
/// ranged response that says there is more. Enough for the element to
/// load and start, not enough to finish; measured on the FLAC fixture,
/// a quarter of it never got past loading.
async function cutShort(route: Route): Promise<void> {
  const whole = await route.fetch();
  const body = await whole.body();
  const cut = Math.floor(body.length * 0.7);
  await route.fulfill({
    status: 206,
    headers: {
      'content-type': whole.headers()['content-type'] ?? 'application/octet-stream',
      'accept-ranges': 'bytes',
      'content-range': `bytes 0-${cut - 1}/${body.length}`,
      'content-length': String(cut),
    },
    body: body.subarray(0, cut),
  });
}
