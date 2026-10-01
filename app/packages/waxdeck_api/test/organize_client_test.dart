import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;
import 'package:waxdeck_api/src/mapping.dart';

/// Answers every request with 204 and records it.
class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(null), 204);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('a profile name reaches the path whole', () async {
    final adapter = _RecordingAdapter();
    final client = WaxDeckClient(
      baseUrl: 'http://host:4420',
      dio: Dio()..httpClientAdapter = adapter,
    );
    await client.deleteOrganizeProfile('C# layout?');
    final uri = adapter.requests.single.uri;
    expect(uri.pathSegments.last, 'C# layout?');
    expect(uri.hasFragment, isFalse);
    expect(uri.hasQuery, isFalse);
  });

  test('a saved profile carries what it sets itself', () {
    final profile = organizeProfileFromGen(
      gen.OrganizeProfile(
        (b) => b
          ..name = 'flat'
          ..musicTemplate = '{title}.{ext}'
          ..audiobookTemplate = '{author}/{title}.{ext}'
          ..podcastTemplate = '{podcast}/{episode}.{ext}'
          ..tagWrite = false
          ..builtIn = false
          ..sample.music = 'a'
          ..sample.audiobook = 'b'
          ..sample.podcast = 'c'
          ..saved.musicTemplate = '{title}.{ext}'
          ..saved.audiobookTemplate = ''
          ..saved.podcastTemplate = '',
      ),
    );
    expect(profile.saved?.music, '{title}.{ext}');
    expect(profile.saved?.audiobook, '');
  });
}
