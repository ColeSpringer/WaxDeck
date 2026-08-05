# Reverse proxy guide

WaxDeck serves everything on one origin: the web app, the REST API,
the WebSocket event channel, media streaming, share pages, and the
compatibility APIs all listen on port 4420. Put a TLS-terminating
reverse proxy in front before exposing it beyond your LAN, and proxy
the whole origin; do not try to route path-by-path.

Four things trip generic proxy configs:

1. **WebSockets.** `/api/v1/ws` carries live sync and the remote
   control bus. The proxy must forward Upgrade requests.
2. **Streaming and long responses.** Audio streams, radio proxying,
   and job event streams are long-lived and unbuffered. Disable
   response buffering and give them generous or unlimited read
   timeouts.
3. **Upload sizes.** Chunked uploads and backup imports post large
   bodies; raise the body-size limit.
4. **App locations are paths.** `/music/albums/al-...` is a screen,
   not a file. WaxDeck answers those itself; a proxy that tries to
   serve or validate them breaks every deep link. See below.

After the proxy is up, set these on the server:

```sh
WAXDECK_PUBLIC_BASE=https://wax.example.com   # OIDC callbacks, share page previews
WAXDECK_COOKIE_SECURE=true                    # cookies are HTTPS-only
```

Do not add CORS headers at the proxy. The API is same-origin by
design; a permissive CORS layer breaks the CSRF model.

The web app is a cross-origin-isolated WebAssembly build and the
server already sends the required COOP and COEP headers; pass response
headers through untouched.

## Deep links and the single-page fallback

Every screen has a real URL - `https://wax.example.com/music/albums/al-01J...`
- and none of those paths is a file on disk. WaxDeck does the
single-page fallback itself: a request for an unknown path that is a
document navigation gets `index.html`, and the app routes from there.
Anything that is not a navigation (a font, the wasm bundle, an icon)
still gets a 404, deliberately: handing HTML to a font loader fails
later and stranger, and the engine's own fallback machinery is pointed
at an unrouted path expecting exactly that 404.

The configurations below need nothing added for this - they proxy the
whole origin, and the fallback happens behind them. What breaks it is
adding a fallback of your own:

- **nginx**: no `try_files` and no `root` on the WaxDeck location. A
  `try_files $uri $uri/ =404` in front of `proxy_pass` answers 404 for
  every deep link, because nothing under those paths exists on the
  proxy's filesystem.
- **Caddy**: no `file_server`, no `try_files`, and no `root` directive.
  `reverse_proxy` alone is the whole configuration.
- **Traefik**: no `errors` middleware remapping 404 to a page of its
  own, and no static `file` provider serving the same host. A 404 from
  WaxDeck is a real 404 (a missing asset) and should reach the browser
  as one.

Two other rules of the same kind. Do not normalize or rewrite paths:
pids are case-sensitive ULIDs, and a lowercasing proxy does not produce
a 404 you can grep for - the lowercased path is still a navigation, so
the fallback answers 200 with the shell and the app reports that the
item does not exist. "Every link says the album is gone" is what path
normalization looks like from the outside. And do not strip query
strings - `/search?q=...` is a shareable result set.

To check a deployment, ask for a location the app owns and nothing on
disk answers. It should return the shell, not a 404:

```sh
curl -s -o /dev/null -w '%{http_code} %{content_type}\n' \
  -H 'Sec-Fetch-Mode: navigate' https://wax.example.com/settings/playback
# 200 text/html; charset=utf-8
```

A 404 here means something in front of WaxDeck is trying to serve the
path itself.

## Caddy

```caddyfile
wax.example.com {
    reverse_proxy 127.0.0.1:4420 {
        flush_interval -1
    }
    request_body {
        max_size 4GB
    }
}
```

Caddy forwards WebSockets automatically.

## nginx

```nginx
server {
    listen 443 ssl http2;
    server_name wax.example.com;

    # certificates ...

    client_max_body_size 4g;

    location / {
        proxy_pass http://127.0.0.1:4420;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_buffering off;
        proxy_read_timeout 1d;
        proxy_send_timeout 1d;
    }
}

# in the http block:
map $http_upgrade $connection_upgrade {
    default upgrade;
    ""      close;
}
```

## Traefik

```yaml
http:
  routers:
    waxdeck:
      rule: "Host(`wax.example.com`)"
      service: waxdeck
      tls: {}
  services:
    waxdeck:
      loadBalancer:
        servers:
          - url: "http://127.0.0.1:4420"
        responseForwarding:
          flushInterval: "-1"
```

Traefik forwards WebSockets automatically and has no default body
limit.

## Subpath hosting

Hosting under a subpath (`https://example.com/wax/`) is not
supported. The web app, media URLs, and share links are all rooted at
the origin. Use a dedicated hostname.

## Cast devices and the proxy

LAN cast devices (Chromecast, DLNA) fetch media over plain LAN HTTP
directly from the server, never through your public proxy. That path
is governed by `WAXDECK_ADVERTISE_BASE` and works even when the proxy
is internet-facing; see the connect and casting page.
