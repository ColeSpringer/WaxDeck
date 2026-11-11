import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

(WaxDeckClient, RecordingAdapter) _client(int status, Object body) {
  final adapter = RecordingAdapter(status: status, body: body);
  return (clientOn(adapter), adapter);
}

/// The media type a recorded request carried in its JSON body.
Object? _sentMediaType(RequestOptions request) {
  final data = request.data;
  final body = data is String ? jsonDecode(data) : data;
  return (body as Map<String, Object?>)['mediaType'];
}

const _refused = {'code': 'invalid-request', 'message': 'refused'};

void main() {
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
