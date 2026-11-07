import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [ScrobblingApi] for `FakeRepository`.
mixin FakeScrobbling on FakeRepositoryState implements ScrobblingApi {
  /// Thrown by [connectListenBrainz] when set.
  WaxDeckApiException? connectError;

  @override
  Future<List<Scrobbler>> listScrobblers() async => scrobblers;

  @override
  Future<Scrobbler> connectListenBrainz(String token, {String? apiUrl}) async {
    final error = connectError;
    if (error != null) throw error;
    final connected = Scrobbler(
      service: 'listenbrainz',
      available: true,
      connected: true,
      username: 'listener',
      apiUrl: apiUrl,
    );
    scrobblers = [
      for (final s in scrobblers)
        if (s.service == 'listenbrainz') connected else s,
    ];
    return connected;
  }

  @override
  Future<void> disconnectListenBrainz() async {
    scrobblers = [
      for (final s in scrobblers)
        if (s.service == 'listenbrainz')
          const Scrobbler(
            service: 'listenbrainz',
            available: true,
            connected: false,
          )
        else
          s,
    ];
  }

  @override
  Future<String> startLastfmConnect() async =>
      'https://last.fm/api/auth/?api_key=fake';

  @override
  Future<void> disconnectLastfm() async {
    scrobblers = [
      for (final s in scrobblers)
        if (s.service == 'lastfm')
          const Scrobbler(service: 'lastfm', available: true, connected: false)
        else
          s,
    ];
  }
}
