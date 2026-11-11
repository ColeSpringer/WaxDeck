import 'dart:convert';

import 'package:test/test.dart';
import 'package:waxdeck_api/src/gen/codec.g.dart';
import 'package:waxdeck_api/src/wire.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

void main() {
  test('a library says whether it is configured, reachable and writable', () {
    LibraryInfo listed(Map<String, Object?> json) => decodeLibraryInfo({
      'pid': 'lb-1',
      'name': 'music',
      'readOnly': false,
      'managed': true,
      ...json,
    }, const WireContext(baseUrl: 'http://host:4420'));
    final flagged = listed({
      'configured': true,
      'unreachable': true,
      'writable': false,
    });
    expect(flagged.configured, isTrue);
    expect(flagged.unreachable, isTrue);
    expect(flagged.writable, isFalse);
    final plain = listed({});
    expect(plain.configured, isFalse);
    expect(plain.unreachable, isFalse);
    expect(plain.writable, isNull);
  });

  test('a folder mounted later reaches the create', () async {
    final adapter = RecordingAdapter(
      status: 201,
      body: <String, Object?>{
        'pid': 'lb-2',
        'name': 'later',
        'readOnly': false,
        'managed': false,
        'path': '/srv/later',
      },
    );
    final created = await clientOn(
      adapter,
    ).createLibrary(name: 'later', path: '/srv/later', allowAbsent: true);
    expect(created.pid, 'lb-2');
    final sent = adapter.requests.single.data;
    expect((sent is String ? jsonDecode(sent) : sent)['allowAbsent'], isTrue);
  });

  test('a removal deletes the library and answers its job', () async {
    final adapter = RecordingAdapter(
      status: 202,
      body: <String, Object?>{
        'pid': 'jb-1',
        'kind': 'remove-root',
        'state': 'running',
        'target': <String, Object?>{'type': 'library', 'pid': 'lb-2'},
      },
    );
    final job = await clientOn(adapter).removeLibrary('lb-2');
    final request = adapter.requests.single;
    expect(request.method, 'DELETE');
    expect(request.uri.path, endsWith('/libraries/lb-2'));
    expect(job.kind, 'remove-root');
    expect(job.target?.pid, 'lb-2');
  });

  // An answer was had, so this is no outage: the outboxes must not
  // queue a change the server took.
  test('an answer that does not decode fails with its status', () async {
    final adapter = RecordingAdapter(
      status: 200,
      body: <String, Object?>{
        'pid': 'lb-2',
        'name': 'later',
        'readOnly': false,
        'managed': false,
      },
    );
    await expectLater(
      clientOn(adapter).setLibraryMedia('lb-2', 'music'),
      throwsA(
        isA<WaxDeckApiException>()
            .having((e) => e.code, 'code', 'transport-decode')
            .having(
              (e) => e.message,
              'message',
              'LibraryInfo.scanStarted: missing',
            )
            .having((e) => e.statusCode, 'statusCode', 200)
            .having((e) => e.unreachable, 'unreachable', isFalse),
      ),
    );
  });
}
