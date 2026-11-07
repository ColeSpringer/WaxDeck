import '../models.dart';

/// Radio stations and saved songs.
abstract interface class RadioApi {
  /// `GET /radio/stations`: the shared station library.
  Future<List<RadioStation>> listRadioStations();

  /// `POST /radio/stations`: adds a station.
  Future<RadioStation> createRadioStation({
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  });

  /// `PUT /radio/stations/{pid}`: replaces a station's fields.
  Future<RadioStation> updateRadioStation(
    String pid, {
    required String name,
    required String streamUrl,
    String? homepageUrl,
    String? logoUrl,
  });

  /// `DELETE /radio/stations/{pid}`: removes a station.
  Future<void> deleteRadioStation(String pid);

  /// `GET /radio/stations/{pid}/play-info`: a tokenized proxied stream
  /// URL, absolute against the client base URL.
  Future<RadioPlayInfo> getRadioPlayInfo(String pid);

  /// `GET /radio/saved`: the caller's own saved songs, newest first.
  Future<RadioSavedSongPage> listRadioSavedSongs({String? cursor, int? limit});

  /// `POST /radio/saved`: keeps the announcement the listener is looking
  /// at. [nowPlaying] is the line they saw rather than whatever the
  /// station is announcing by the time the request lands, because a
  /// station rolls over between polls. Idempotent on the song's
  /// identity, so a second save answers the row already held - which is
  /// what makes the heart a toggle.
  Future<RadioSavedSong> saveRadioSong({
    required String stationPid,
    required String nowPlaying,
  });

  /// `DELETE /radio/saved/{pid}`: drops a saved song. Dropping one that
  /// is already gone succeeds.
  Future<void> deleteRadioSavedSong(String pid);

  /// `GET /radio/directory`: searches the public station directory.
  Future<List<RadioDirectoryEntry>> searchRadioDirectory(
    String query, {
    int? limit,
  });
}
