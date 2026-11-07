import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [MediaUrlsApi] for `FakeRepository`.
mixin FakeMediaUrls on FakeRepositoryState implements MediaUrlsApi {
  @override
  String artUrlFor(String pid, {String? role}) {
    final query = <String, String>{
      if (role != null && role != 'front') 'role': role,
    };
    return Uri(
      path: '/api/v1/items/$pid/art',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
  }

  @override
  String radioLogoUrlFor(String pid) => '/api/v1/radio/stations/$pid/logo';

  @override
  String radioNowPlayingArtUrlFor(String pid, String key) =>
      '/api/v1/radio/stations/$pid/now-playing-art?v=$key';

  @override
  String radioSavedArtUrlFor(String pid) => '/api/v1/radio/saved/$pid/art';

  @override
  String backupArchiveUrl(String backupId) =>
      '/api/v1/admin/backups/$backupId/archive';

  /// Every set of exit requests built, so a test can assert what a
  /// closing tab would have sent without a browser to close.
  final List<List<ExitRequest>> exitBuilds = [];

  /// The CSRF token this fake authenticates with, as the real client
  /// does after a web sign-in. Present so a test can assert the beacons
  /// carry a credential: nothing waits for one of these, so a request
  /// that goes out unauthenticated fails invisibly.
  String? csrfToken = 'csrf-test-token';

  @override
  List<ExitRequest> exitRequests({
    String? pid,
    int? positionMs,
    ListenSession? listen,
    List<String> timelinePids = const <String>[],
  }) {
    final headers = <String, String>{'X-CSRF-Token': ?csrfToken};
    final built = <ExitRequest>[
      if (pid != null && positionMs != null)
        ExitRequest(
          path: '/api/v1/items/${Uri.encodeComponent(pid)}/play-state',
          method: 'PUT',
          body: '{"positionMs":$positionMs}',
          headers: headers,
        ),
      if (listen != null)
        ExitRequest(
          path: '/api/v1/listens',
          method: 'POST',
          body: '{"sessions":[{"sessionId":"${listen.sessionId}"}]}',
          headers: headers,
        ),
      for (final pid in timelinePids)
        ExitRequest(
          path: '/api/v1/player/timeline/$pid',
          method: 'DELETE',
          body: '',
          headers: headers,
        ),
    ];
    exitBuilds.add(built);
    return built;
  }
}
