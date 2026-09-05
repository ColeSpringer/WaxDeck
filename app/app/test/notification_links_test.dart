import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/routes.dart';

/// The server builds a link into this app for every notification it
/// delivers, and it does that from a table of its own: a Go server
/// cannot read a Dart constant, so `service/notify.go` writes the paths
/// out a second time. This is the join between the two copies - a route
/// renamed here without the server following fails over here rather
/// than shipping a notification whose link 404s.
String _serverLinkTable() {
  final path = _repoFile('server/internal/service/notify.go');
  final source = File(path).readAsStringSync();
  const opening = 'func (l *Library) notificationLink(';
  final start = source.indexOf(opening);
  if (start < 0) throw StateError('notificationLink is no longer in notify.go');
  final end = source.indexOf('\n}', start);
  if (end < 0) throw StateError('notificationLink no longer ends as it did');
  return source.substring(start, end);
}

String _repoFile(String relative) {
  var dir = Directory.current;
  for (var up = 0; up < 6; up++) {
    final candidate = File('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  throw StateError('no $relative above ${Directory.current.path}');
}

void main() {
  final table = _serverLinkTable();

  /// Every path the server can build, against the route it must be.
  final expected = <String, String>{
    'review-ready': WaxRoute.review,
    'signup-requested': WaxRoute.users,
    'backup-completed': WaxRoute.backups,
    'backup-failed': WaxRoute.backups,
    'import-completed': WaxRoute.review,
    'feed-disabled': WaxRoute.podcasts,
    'episode-downloaded': WaxRoute.podcasts,
    'playlist-synced': WaxRoute.playlists,
  };

  test('the server links to locations this app answers', () {
    for (final entry in expected.entries) {
      expect(
        table,
        contains('"${entry.key}"'),
        reason: 'the server no longer links ${entry.key} anywhere',
      );
      expect(
        table,
        contains('"${entry.value}"'),
        reason:
            '${entry.key} should link to ${entry.value}, which the server '
            'table does not name',
      );
    }
  });

  test('the entity links are built from the same prefixes', () {
    // The pid-carrying half. Written as the prefix the route builder
    // uses, so a route whose shape changes (a segment added, a prefix
    // renamed) shows up here rather than in a dead link.
    final prefixes = <String>{
      '${WaxRoute.review}/',
      '${WaxRoute.podcasts}/',
      WaxRoute.episodePrefix,
      '${WaxRoute.playlists}/',
    };
    for (final prefix in prefixes) {
      expect(
        table,
        contains('"$prefix"'),
        reason: 'the server builds no link under $prefix',
      );
    }
  });
}
