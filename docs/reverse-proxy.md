# Reverse proxy guide

WaxDeck serves everything on one origin: the web app, the REST API,
the WebSocket event channel, media streaming, share pages, and the
compatibility APIs all listen on port 4420. Put a TLS-terminating
reverse proxy in front before exposing it beyond your LAN, and proxy
the whole origin; do not try to route path-by-path.

Three things trip generic proxy configs:

1. **WebSockets.** `/api/v1/ws` carries live sync and the remote
   control bus. The proxy must forward Upgrade requests.
2. **Streaming and long responses.** Audio streams, radio proxying,
   and job event streams are long-lived and unbuffered. Disable
   response buffering and give them generous or unlimited read
   timeouts.
3. **Upload sizes.** Chunked uploads and backup imports post large
   bodies; raise the body-size limit.

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
