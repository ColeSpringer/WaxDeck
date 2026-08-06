// The suite's server-side hand, typed against the contract itself.
//
// Two hundred-odd `/api/v1/...` string literals used to sit in the
// specs. One of them was a typo, and a typo in a URL is a 404 that reads
// as a missing feature: the spec fails on the assertion after it, in a
// screen that never loaded, and the search starts in the app. That whole
// class is a compile error here - a path that is not in
// `api/openapi.yaml` is not assignable, so a renamed or removed endpoint
// fails `npm run typecheck` and names itself.
//
// The version prefix is written once, below. Response bodies come back
// typed from the same generated file, so a field the server stopped
// sending is a compile error too, exactly as the Dart client's generated
// DTOs already are (ADR-0002).

import { APIRequestContext, APIResponse, expect } from '@playwright/test';
import type { paths } from '../api-types';

/// The one place the API version lives.
const ROOT = '/api/v1';

type Paths = paths;
type PathOf<M extends string> = {
  [P in keyof Paths]: Paths[P] extends { [K in M]: object } ? P : never;
}[keyof Paths];

type Operation<P extends keyof Paths, M extends string> = P extends keyof Paths
  ? M extends keyof Paths[P]
    ? Paths[P][M]
    : never
  : never;

/// The JSON body of whichever 2xx the operation declares. `unknown` when
/// it declares none (a 204), which makes ignoring the result the only
/// thing a caller can do with it.
type Body<T> = T extends { responses: infer R }
  ? R extends { 200: { content: { 'application/json': infer B } } }
    ? B
    : R extends { 201: { content: { 'application/json': infer B } } }
      ? B
      : R extends { 202: { content: { 'application/json': infer B } } }
        ? B
        : unknown
  : unknown;

/// The path placeholders the operation declares, so `{showPid}` cannot
/// be forgotten or misspelled.
type PathParams<T> = T extends { parameters: { path: infer P } }
  ? P extends null | undefined
    ? Record<string, never>
    : P
  : Record<string, never>;

type QueryParams<T> = T extends { parameters: { query?: infer Q } }
  ? Q extends null | undefined
    ? Record<string, never>
    : NonNullable<Q>
  : Record<string, never>;

/// The JSON body the operation declares it takes. `never` when it takes
/// none, so passing one is an error rather than a silent no-op - and a
/// misspelled field is an error rather than a 400 the spec discovers at
/// runtime.
/// openapi-typescript spells the three cases apart: an operation that
/// takes no body emits `requestBody?: never`, a required body emits
/// `requestBody: {...}`, an optional one `requestBody?: {...}`. The
/// optional forms both match a `requestBody?:` pattern, so the body type
/// is dug out of the property rather than pattern-matched on the
/// operation - `never` for the first case, which is what makes passing
/// `data` to a GET an error rather than a silent no-op.
/// The is-never check is not decoration. `requestBody?: never` makes the
/// property's type `undefined`, so `NonNullable` of it is `never` - and
/// `never` extends every shape, which would leave `infer B` unresolved
/// as `unknown` and let a GET take any body at all.
type RequestBody<T> = T extends { requestBody?: infer R }
  ? [NonNullable<R>] extends [never]
    ? never
    : NonNullable<R> extends { content: { 'application/json': infer B } }
      ? B
      : never
  : never;

type Options<T> = {
  path?: PathParams<T>;
  query?: QueryParams<T>;
  data?: RequestBody<T>;
  headers?: Record<string, string>;
};

/// Bearer, not cookie: a bearer-authenticated call carries no CSRF
/// obligation (the server only demands the synchronizer token from
/// cookie-borne credentials, which ride along on every browser request
/// and so need proof the app itself sent them). The browser half of the
/// suite is the cookie half; this is the spec's own hand.
///
/// An empty token sends no header at all rather than an empty bearer.
/// Two callers mean it: the spec whose subject is a server with no
/// accounts on it, and a hand built over the browser's own request
/// context, where the session cookie is what should be doing the
/// authenticating. `Bearer ` with nothing after it is a credential the
/// server refuses, which would read as a permission failure in both.
export const authed = (token: string): { headers: Record<string, string> } =>
  token === '' ? { headers: {} } : { headers: { Authorization: `Bearer ${token}` } };

function fill(template: string, params: Record<string, unknown> | undefined) {
  const url = template.replace(/\{([^}]+)\}/g, (_, name: string) => {
    const value = params?.[name];
    // A placeholder left unfilled would go to the server as the literal
    // `{showPid}` and come back 404 - the exact failure this file
    // exists to make impossible, so it is an error here instead.
    expect(value, `path parameter {${name}} for ${template}`).toBeDefined();
    return encodeURIComponent(String(value));
  });
  return `${ROOT}${url}`;
}

function query(url: string, params: Record<string, unknown> | undefined) {
  if (params === undefined) return url;
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    if (Array.isArray(value)) for (const v of value) search.append(key, String(v));
    else search.set(key, String(value));
  }
  const encoded = search.toString();
  return encoded === '' ? url : `${url}?${encoded}`;
}

/// Every call, as the raw response. For a spec asserting a status - a
/// 409 on a taken name, a 403 behind a permission - rather than reading
/// a body.
export class RawApi {
  constructor(
    private readonly request: APIRequestContext,
    private readonly token: string,
  ) {}

  get<P extends PathOf<'get'>>(path: P, options: Options<Operation<P, 'get'>> = {}) {
    return this.send('get', path as string, options as never);
  }
  post<P extends PathOf<'post'>>(path: P, options: Options<Operation<P, 'post'>> = {}) {
    return this.send('post', path as string, options as never);
  }
  put<P extends PathOf<'put'>>(path: P, options: Options<Operation<P, 'put'>> = {}) {
    return this.send('put', path as string, options as never);
  }
  patch<P extends PathOf<'patch'>>(path: P, options: Options<Operation<P, 'patch'>> = {}) {
    return this.send('patch', path as string, options as never);
  }
  delete<P extends PathOf<'delete'>>(path: P, options: Options<Operation<P, 'delete'>> = {}) {
    return this.send('delete', path as string, options as never);
  }

  /// An absolute or already-built URL the server itself minted - a share
  /// link, a media relay URL, a `nextCursor` page. Typing those would
  /// mean typing the server's own strings, which is not a contract this
  /// file can hold.
  minted(url: string, options: { headers?: Record<string, string> } = {}) {
    return this.request.get(url, {
      headers: { ...authed(this.token).headers, ...options.headers },
    });
  }

  private send(
    method: 'get' | 'post' | 'put' | 'patch' | 'delete',
    path: string,
    // Untyped internally on purpose: the public methods above are where
    // the contract is enforced, and re-stating it here would only mean
    // proving the same thing twice to the same compiler.
    options: {
      path?: Record<string, unknown>;
      query?: Record<string, unknown>;
      data?: unknown;
      headers?: Record<string, string>;
    },
  ): Promise<APIResponse> {
    const url = query(fill(path, options.path), options.query);
    const init = {
      headers: { ...authed(this.token).headers, ...options.headers },
      ...(options.data === undefined ? {} : { data: options.data }),
    };
    return this.request[method](url, init);
  }
}

/// The everyday hand: calls that must succeed, answering their parsed
/// body. A non-2xx fails here with the server's own error body, which is
/// the message worth having - not a `toBeTruthy` three lines later on
/// something that was never fetched.
export class Api {
  readonly raw: RawApi;

  constructor(
    private readonly request: APIRequestContext,
    readonly token: string,
  ) {
    this.raw = new RawApi(request, token);
  }

  /// The same server and the same connection, spoken to with a different
  /// bearer: nobody at all (an empty token sends no header), or a
  /// credential that is not a session - the similarity worker's shared
  /// token, an app password.
  ///
  /// The connection is shared, and that is the part to hold in mind: one
  /// `APIRequestContext` means one cookie jar, so a login made through
  /// `as('')` leaves a session cookie that every later call on this hand
  /// carries. An empty token is therefore "no Authorization header",
  /// which is not the same claim as "unauthenticated" once anything on
  /// this hand has logged in. A spec that needs provable anonymity -
  /// asserting a 401 - takes `anonApi`, which has a jar of its own and
  /// never logs in.
  as(token: string): Api {
    return new Api(this.request, token);
  }

  async get<P extends PathOf<'get'>>(
    path: P,
    options: Options<Operation<P, 'get'>> = {},
  ): Promise<Body<Operation<P, 'get'>>> {
    return this.json(await this.raw.get(path, options), 'GET', path as string);
  }

  /// The body if the call succeeded, `undefined` if it did not.
  ///
  /// For polling, and only for polling. `expect.poll` does not catch a
  /// callback that throws - it fails the assertion on the first attempt,
  /// with no retry - so a poll built on `get` is one transient 503 away
  /// from reporting a permanent failure. Anywhere else, a non-2xx is a
  /// defect and `get` throwing it with the server's own body is what you
  /// want.
  async tryGet<P extends PathOf<'get'>>(
    path: P,
    options: Options<Operation<P, 'get'>> = {},
  ): Promise<Body<Operation<P, 'get'>> | undefined> {
    const resp = await this.raw.get(path, options);
    if (!resp.ok()) return undefined;
    const text = await resp.text();
    if (text === '') return undefined;
    try {
      return JSON.parse(text) as Body<Operation<P, 'get'>>;
    } catch {
      // A 2xx that is not JSON. The server's SPA fallback answers any
      // path its mux does not match with index.html at 200, so a route
      // that was removed or misspelled comes back as HTML that `ok()`
      // is perfectly happy with - and a parse error thrown from inside
      // `expect.poll` is not retried, it ends the poll. This method's
      // whole contract is that it never does that.
      return undefined;
    }
  }

  async post<P extends PathOf<'post'>>(
    path: P,
    options: Options<Operation<P, 'post'>> = {},
  ): Promise<Body<Operation<P, 'post'>>> {
    return this.json(await this.raw.post(path, options), 'POST', path as string);
  }

  async put<P extends PathOf<'put'>>(
    path: P,
    options: Options<Operation<P, 'put'>> = {},
  ): Promise<Body<Operation<P, 'put'>>> {
    return this.json(await this.raw.put(path, options), 'PUT', path as string);
  }

  async patch<P extends PathOf<'patch'>>(
    path: P,
    options: Options<Operation<P, 'patch'>> = {},
  ): Promise<Body<Operation<P, 'patch'>>> {
    return this.json(await this.raw.patch(path, options), 'PATCH', path as string);
  }

  async delete<P extends PathOf<'delete'>>(
    path: P,
    options: Options<Operation<P, 'delete'>> = {},
  ): Promise<Body<Operation<P, 'delete'>>> {
    return this.json(await this.raw.delete(path, options), 'DELETE', path as string);
  }

  private async json<T>(resp: APIResponse, method: string, path: string): Promise<T> {
    if (!resp.ok()) {
      throw new Error(
        `${method} ${path} answered ${resp.status()}: ${await resp.text()}`,
      );
    }
    // 204, and the handful of 200s with no body: the operation's
    // declared type is `unknown` for those, so a caller cannot read
    // anything off what comes back.
    const text = await resp.text();
    return (text === '' ? undefined : JSON.parse(text)) as T;
  }
}
