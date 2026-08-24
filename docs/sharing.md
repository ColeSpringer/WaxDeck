# Public share links

A share link makes one track, album, playlist, book, or episode
reachable by anyone holding the URL: no account, no app. Paste it in a
chat and the recipient gets a page with artwork and a play button that
works in any browser.

## How links work

`POST /api/v1/shares` creates a link for a track, album, book, or
episode you can see, or a playlist you own. An album share opens the
album's tracks in order; the album screen's overflow and the item menus
on track rows offer it. Playlists require ownership: the
public page serves the owner's member view for the link's whole life,
so another user's shared playlist is theirs to publish, not yours.
The URL is a signed capability: possession is the authorization,
until the link expires or you revoke it. `GET /api/v1/shares` lists your links
(administrators can list everyone's with `all=true`), and
`DELETE /api/v1/shares/{id}` revokes one immediately.

Options at creation:

- `expiresInHours` - lifetime; omitted means the link lives until
  revoked.
- `allowDownload` - offer the original file on the page. Requires
  your own download permission.
- `positionMs` - for episodes, copy-link-at-timestamp: the page
  starts playback at that position.

Episodes of private feeds (feeds with credentials) refuse to be
shared: a capability URL must never leak paid content.

## The landing page

Share pages at `/s/{token}` are server-rendered plain HTML: an audio
element per entry, artwork, and OpenGraph tags so messaging apps
render a proper preview card. They never load the web app, which is
exactly why they open instantly on an app-less phone. Set
`WAXDECK_PUBLIC_BASE` so preview images resolve absolutely.

## Abuse controls

A public link must never become a free resource faucet, so:

- Anonymous playback that engages the transcoder is billed against
  the owner's transcode limits, and lossy encodes honor the owner's
  bitrate cap.
- Each link serves a small number of concurrent streams; more
  listeners get a try-again answer.
- Pages send `Referrer-Policy: no-referrer` (the capability URL never
  leaks through outbound links) and `X-Robots-Tag: noindex`.
- Nothing secret is stored: the URL token derives from the share id
  and the server key, so a leaked database exposes no working links,
  and your listing can always show full URLs.

