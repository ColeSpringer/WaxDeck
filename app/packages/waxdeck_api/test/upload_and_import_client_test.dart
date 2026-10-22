import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// Answers every request with one canned body and records it.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.status, this.body);

  final int status;
  final Object body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(WaxDeckClient, _RecordingAdapter) _client(int status, Object body) {
  final adapter = _RecordingAdapter(status, body);
  final dio = Dio()..httpClientAdapter = adapter;
  return (WaxDeckClient(baseUrl: 'http://example.invalid', dio: dio), adapter);
}

/// The media type a recorded request carried in its JSON body.
Object? _sentMediaType(RequestOptions request) {
  final data = request.data;
  final body = data is String ? jsonDecode(data) : data;
  return (body as Map<String, Object?>)['mediaType'];
}

const _refused = {'code': 'invalid-request', 'message': 'refused'};

void main() {
  test('an OPML import is given the long-operation budget', () async {
    // The server subscribes the feeds one after another before it
    // answers, so the ordinary 30 s would cut a slow import off.
    final (client, adapter) = _client(200, {'results': <Object>[]});
    expect(await client.importOpml('<opml version="2.0"/>'), isEmpty);
    expect(adapter.requests.single.receiveTimeout, const Duration(minutes: 30));
  });

  group('upload media types', () {
    for (final mediaType in const [MediaType.music, MediaType.audiobook]) {
      test('${mediaType.wireName} goes out as itself', () async {
        final (client, adapter) = _client(400, _refused);
        await expectLater(
          client.createAcquisition(
            url: 'https://example.com/a',
            mediaType: mediaType,
          ),
          throwsA(isA<WaxDeckApiException>()),
        );
        await expectLater(
          client.createUpload(
            fileName: 'a.flac',
            sizeBytes: 1,
            mediaType: mediaType.wireName,
          ),
          throwsA(isA<WaxDeckApiException>()),
        );
        await expectLater(
          client.createUploadBatch(
            grouping: UploadGrouping.album,
            mediaType: mediaType.wireName,
          ),
          throwsA(isA<WaxDeckApiException>()),
        );
        expect(adapter.requests.map(_sentMediaType), [
          mediaType.wireName,
          mediaType.wireName,
          mediaType.wireName,
        ]);
      });
    }

    test('a podcast is refused before anything is sent', () async {
      final (client, adapter) = _client(400, _refused);
      await expectLater(
        client.createAcquisition(
          url: 'https://example.com/a',
          mediaType: MediaType.podcast,
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.createUpload(
          fileName: 'a.mp3',
          sizeBytes: 1,
          mediaType: 'podcast',
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.createUploadBatch(
          grouping: UploadGrouping.album,
          mediaType: 'podcast',
        ),
        throwsArgumentError,
      );
      expect(adapter.requests, isEmpty);
    });
  });
}
