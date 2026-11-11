import 'dart:io';

import 'package:test/test.dart';
import 'package:waxdeck_api/src/hand_models.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

/// The paths this package types by hand rather than through the generated
/// calls, each held to its operation in the committed bundle.
void main() {
  final spec = _Spec.read();
  const base = 'http://host:4420';
  final client = clientOn(RecordingAdapter(), baseUrl: base);

  /// Expects [url] to be [operationId]'s template under the server root,
  /// its parameters filled from [params], every query name it carries one
  /// the operation declares, and [method] its method.
  void expectOperation(
    String url,
    String operationId, {
    Map<String, String> params = const {},
    String? method,
  }) {
    final operation = spec.operations[operationId];
    expect(operation, isNotNull, reason: '$operationId is in no path');
    var path = operation!.template;
    params.forEach((name, value) => path = path.replaceAll('{$name}', value));
    expect(path, isNot(contains('{')), reason: '$operationId: $path');
    expect(url, startsWith(base));
    expect(Uri.parse(url).path, '${spec.root}$path', reason: operationId);
    for (final name in Uri.parse(url).queryParametersAll.keys) {
      expect(
        operation.query,
        contains(name),
        reason: '$operationId declares no query parameter $name',
      );
    }
    if (method != null) expect(method, operation.method, reason: operationId);
  }

  test('the bundle names its server root and operations', () {
    // A guard on the guard: a read that found nothing would pass nothing.
    expect(spec.root, startsWith('/'));
    expect(spec.operations.length, greaterThan(100));
    expect(spec.operations['getItemArt']?.query, containsAll(['role', 'size']));
    expect(spec.operations['getRadioNowPlayingArt']?.query, contains('v'));
  });

  test('the media URLs are their operations\' paths', () {
    expectOperation(
      client.artUrlFor('tr-1'),
      'getItemArt',
      params: {'pid': 'tr-1'},
    );
    expectOperation(
      client.artUrlFor('al-1', role: 'back'),
      'getItemArt',
      params: {'pid': 'al-1'},
    );
    expectOperation(
      client.radioLogoUrlFor('rs-1'),
      'getRadioStationLogo',
      params: {'pid': 'rs-1'},
    );
    expectOperation(
      client.radioNowPlayingArtUrlFor('rs-1', 'k1'),
      'getRadioNowPlayingArt',
      params: {'pid': 'rs-1'},
    );
    expectOperation(
      client.radioSavedArtUrlFor('rx-1'),
      'getRadioSavedSongArt',
      params: {'pid': 'rx-1'},
    );
    expectOperation(
      client.backupArchiveUrl('bk-1'),
      'downloadBackup',
      params: {'backupId': 'bk-1'},
    );
  });

  test('a playlist\'s art is its operation\'s path', () {
    final playlist = decodePlaylist({
      'pid': 'pl-1',
      'name': 'Mix',
      'kind': 'static',
      'visibility': 'private',
      'ownerName': 'ada',
      'isOwner': true,
      'hasArt': true,
      'createdAt': '2024-05-01T10:00:00Z',
      'updatedAt': '2024-05-01T10:00:00Z',
    }, const WireContext(baseUrl: base));
    expectOperation(playlist.artUrl!, 'getItemArt', params: {'pid': 'pl-1'});
  });

  test('the exit requests are their operations\' paths and methods', () {
    final sent = client.exitRequests(
      pid: 'tr-1',
      positionMs: 5,
      listen: ListenSession(
        sessionId: 'ls-1',
        pid: 'tr-1',
        startedAt: DateTime.utc(2024, 5, 1),
        msPlayed: 5,
      ),
      timelinePids: const ['tl-1'],
    );
    expect(sent, hasLength(3));
    expectOperation(
      sent[0].path,
      'putPlayState',
      params: {'pid': 'tr-1'},
      method: sent[0].method,
    );
    expectOperation(sent[1].path, 'reportListens', method: sent[1].method);
    expectOperation(
      sent[2].path,
      'releaseQueueTimeline',
      params: {'pid': 'tl-1'},
      method: sent[2].method,
    );
  });
}

/// The bundle's server root, and each operation's method, path template
/// and declared query parameter names, read off its `paths:` block.
/// Parameters shared through a `$ref` are not followed, so a query name
/// worth pinning is declared in the operation itself.
class _Spec {
  _Spec(this.root, this.operations);

  final String root;
  final Map<String, _Operation> operations;

  static _Spec read() {
    final lines = File(_repoFile('api/openapi.yaml')).readAsLinesSync();
    final serverUrl = RegExp(r'^  - url: (\S+)$');
    final pathKey = RegExp(r'^  (/\S*):$');
    final methodKey = RegExp(
      r'^    (get|put|post|delete|patch|head|options):$',
    );
    final operationId = RegExp(r'^      operationId: (\S+)$');
    final paramName = RegExp(r'^        - name: (\S+)$');
    final paramIn = RegExp(r'^          in: (\S+)$');
    String? root;
    final operations = <String, _Operation>{};
    String? section;
    String? path;
    String? method;
    _Operation? operation;
    String? param;
    for (final line in lines) {
      if (line.isNotEmpty && !line.startsWith(' ')) {
        section = line;
        continue;
      }
      if (section == 'servers:') {
        root ??= serverUrl.firstMatch(line)?.group(1);
      }
      if (section != 'paths:') continue;
      if (pathKey.firstMatch(line) case final m?) {
        path = m.group(1);
        method = null;
      } else if (methodKey.firstMatch(line) case final m?) {
        method = m.group(1)!.toUpperCase();
      } else if (operationId.firstMatch(line) case final m?) {
        operation = _Operation(method!, path!);
        operations[m.group(1)!] = operation;
      } else if (paramName.firstMatch(line) case final m?) {
        param = m.group(1);
      } else if (paramIn.firstMatch(line) case final m?) {
        if (m.group(1) == 'query' && param != null) operation?.query.add(param);
        param = null;
      }
    }
    return _Spec(root!, operations);
  }
}

class _Operation {
  _Operation(this.method, this.template);

  final String method;
  final String template;
  final Set<String> query = {};
}

/// A repo-relative path, resolved by walking up from the package, which
/// is where this test runs.
String _repoFile(String relative) {
  var dir = Directory.current;
  for (var up = 0; up < 6; up++) {
    final candidate = File('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  throw StateError('no $relative above ${Directory.current.path}');
}
