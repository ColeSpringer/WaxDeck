/// Turning API models into the design system's plain view data.
///
/// `waxdeck_ui` never imports the API package, so every
/// screen maps at the call site. These are the mappings more than one
/// screen would otherwise write differently: which domain a media type
/// belongs to, what shape its artwork takes, and how a URL becomes an
/// image. Everything else stays at its call site, where the screen knows
/// what its own rows mean.
library;

import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'artwork/artwork_store.dart';

WaxDomain waxDomainOf(MediaType type) => switch (type) {
  MediaType.music => WaxDomain.music,
  MediaType.podcast => WaxDomain.podcasts,
  MediaType.audiobook => WaxDomain.audiobooks,
};

/// Shape is a domain signal that reads at 40 px and survives greyscale.
/// Book covers vary between square (audio sources) and portrait (book
/// sources), so they are fitted on a matte rather than cropped to match
/// music and podcast art, which are square by nature.
ArtworkShape waxShapeOf(MediaType type) => switch (type) {
  MediaType.music || MediaType.podcast => ArtworkShape.square,
  MediaType.audiobook => ArtworkShape.portrait,
};

/// The artwork behind a URL the API already resolved, or null where
/// there is none: the placeholder monogram is a real state, not a
/// loading one.
///
/// The store decides what a URL costs - which size rung to ask the
/// server for, whether the bytes come off the network at all, what the
/// decode is bounded to. Screens only decide where the cover goes.
WaxArtwork? waxArtwork(ArtworkStore store, String? url) => store.source(url);

/// A station's logo, through the server's proxy.
///
/// Never the station host's own URL: on web it offers no CORS headers, an
/// http logo is mixed content on an https page, and the fetch hands the
/// listener's IP to a stranger.
///
/// Asked for unconditionally, and that is the fix rather than an
/// oversight. This used to gate on `logoUrl` being set, on the reasoning
/// that the proxy would only 404 otherwise - but that is every By-URL
/// station and every directory entry whose favicon was blank, SVG, or
/// dead, which is most of them, and they all drew a monogram forever.
/// The server now discovers a logo for a station whose row names none,
/// so a blank `logoUrl` no longer means there is nothing to fetch, and
/// asking is the only way to find out. A genuine miss is still a 404 the
/// monogram covers, and the server caches it so the second paint costs
/// nothing.
///
/// Shared because two copies is how the deck bar's radio face kept
/// fetching from the station after the hub was converted.
WaxArtwork? waxStationLogo(
  ArtworkStore store,
  WaxDeckRepository repository,
  RadioStation station,
) => store.source(repository.radioLogoUrlFor(station.pid));

/// What a radio surface draws: the song's cover where the server matched
/// one, the station's logo otherwise, with the shape that suits whichever
/// answered. A circle suits a logo and a wordmark; a sleeve cropped to
/// one loses its corners, which is most of an album cover.
///
/// Every radio surface uses it - the player face, the deck bar, and the
/// mini window - so the cover appears wherever the station does rather
/// than only full screen. Shared for the reason [waxStationLogo] is: one
/// copy of this left behind is a bar that keeps drawing a logo while the
/// face beside it draws the record.
({WaxArtwork? artwork, ArtworkShape shape, bool onTheRecord}) waxRadioArtwork(
  ArtworkStore store,
  WaxDeckRepository repository,
  RadioStation station,
  String? nowPlayingArtUrl,
) {
  final cover = waxArtwork(store, nowPlayingArtUrl);
  if (cover != null) {
    return (artwork: cover, shape: ArtworkShape.square, onTheRecord: true);
  }
  return (
    artwork: waxStationLogo(store, repository, station),
    shape: ArtworkShape.circle,
    onTheRecord: false,
  );
}
