# Public share links

A share link makes one track, album, playlist, book, or episode
reachable by anyone holding the URL: no account, no app. Paste it in a
chat and the recipient gets a page with artwork and a play button that
works in any browser.

## How links work

`POST /api/v1/shares` creates a link for a track, album, book, or
episode you can see, or a playlist you own. An album share opens the
album's tracks in order; the album screen's overflow and the item menus
on track rows offer it, and it needs at least one track you can hear.
Playlists require ownership: the public page serves the owner's member
view for the link's whole life, so another user's shared playlist is
theirs to publish, not yours. The URL is a signed capability:
possession is the authorization, until the link expires or you revoke
it.

A link serves what its owner can see each time it is opened, never
more. A playlist or album link plays only the members the owner can
still open, and a link whose whole target has left the owner's reach
(a library grant withdrawn, a content setting that now denies it), or
whose owner is disabled, answers as if it did not exist until that
changes back. A track link to a track that joins a book (**Treat as
audiobook** on an album, say) is revoked rather than widened into the
whole book; a link to a lone track that becomes a book follows it. A
track that a scan makes a book, as moving its library onto Audiobooks
does, answers its track links as if it were gone.
Creating a link writes an audit entry naming its target,
and an administrator revoking someone else's link writes another. `GET /api/v1/shares` lists your links
(administrators can list everyone's with `all=true`), and
`DELETE /api/v1/shares/{id}` revokes one immediately.

Options at creation:

- `expiresInHours` - lifetime; omitted means the link lives until
  revoked.
- `allowDownload` - offer the original file on the page. Requires
  your own download permission. An episode the server has not fetched
  has no file here, so its link offers no download.
- `positionMs` - for episodes, copy-link-at-timestamp: the page
  starts playback at that position.

Episodes of private feeds (feeds with credentials) refuse to be
shared: a capability URL must never leak paid content. A playlist link
leaves such episodes out.

An episode the server has not fetched can still be shared, and plays
straight away: the link relays it from the show's own host, and the
listener's address never reaches that host. One whose feed names no
audio the server can relay (a YouTube video, say) cannot be shared
until it is fetched.

## The landing page

Share pages at `/s/{token}` are server-rendered plain HTML: an audio
element per entry, artwork, and OpenGraph tags so messaging apps
render a proper preview card. They never load the web app, which is
exactly why they open instantly on an app-less phone. An entry with
nothing to play yet (a file that has gone missing or been trashed, or a
playlist's episode the server has not fetched and cannot relay) says so
in place of its player. While the catalog is handed to a maintenance
job, a link's page and media answer that the server is briefly busy
(503) rather than that the link is gone. Set `WAXDECK_PUBLIC_BASE` so
preview images resolve absolutely.

## Abuse controls

A public link must never become a free resource faucet, so:

- Anonymous playback that engages the transcoder is billed against
  the owner's transcode limits, and lossy encodes honor the owner's
  bitrate cap. A relayed episode takes one of the owner's relayed
  streams, the same allowance the owner's own listening to unfetched
  episodes and radio draws on; the owner's links together never take
  the last two, so the owner can always listen.
- A relayed episode is only ever audio or video: a host that answers
  with a page, a document, a picture or a playlist instead is refused,
  and media responses tell the browser not to treat them as anything
  else.
- Each link serves a small number of concurrent streams and
  downloads; more listeners get a try-again answer. A visitor who
  stops reading is let go, so a stalled one cannot hold a link's
  streams, while one still reading at the pace audio plays keeps
  playing. The wait is a minute where the player can resume by range
  when it comes back (a file, and a podcast host that takes ranges).
  Audio it cannot resume, such as a track cut from a longer file or a
  podcast host that ignores ranges, waits 15 minutes. A reverse proxy
  in front has to wait on a stalled client for as long, or its own
  timeout decides: nginx's `send_timeout` is a minute by default, and
  the [reverse proxy guide](reverse-proxy.md) raises it.
- Revoking a link, or its reaching its expiry, ends the streams and
  downloads already running on it at once, a paused visitor's and a
  stream waiting on a quiet podcast host included. A link whose owner
  is disabled ends them at the next check: every few seconds while
  audio flows, and otherwise when a stalled visitor's wait or a quiet
  host's half minute runs out.
- A relayed episode that stops before the host's own end (the host
  drops the connection, goes quiet, or sends more than any episode)
  is cut rather than finished, so the player knows to ask for the rest.
- Pages send `Referrer-Policy: no-referrer` (the capability URL never
  leaks through outbound links) and `X-Robots-Tag: noindex`. Every
  answer is `Cache-Control: no-store` so a cache cannot keep serving a
  revoked link; the artwork alone is stored and revalidated at each
  use.
- Nothing secret is stored: the URL token derives from the share id
  and the server key, so a leaked database exposes no working links,
  and your listing can always show full URLs.

