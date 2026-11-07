import '../models.dart';

/// Scrobbler connections.
abstract interface class ScrobblingApi {
  /// `GET /users/me/scrobblers`: the caller's scrobbling connection
  /// slots.
  Future<List<Scrobbler>> listScrobblers();

  /// `PUT /users/me/scrobblers/listenbrainz`: validates and stores a
  /// ListenBrainz token. [apiUrl] points at a compatible server.
  Future<Scrobbler> connectListenBrainz(String token, {String? apiUrl});

  /// `DELETE /users/me/scrobblers/listenbrainz`: disconnects.
  Future<void> disconnectListenBrainz();

  /// `POST /users/me/scrobblers/lastfm/connect`: mints the Last.fm
  /// authorization URL to open in a browser.
  Future<String> startLastfmConnect();

  /// `DELETE /users/me/scrobblers/lastfm`: disconnects.
  Future<void> disconnectLastfm();
}
