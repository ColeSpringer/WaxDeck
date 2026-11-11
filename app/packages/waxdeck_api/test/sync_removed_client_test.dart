import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

void main() {
  test('the pids ride the body and the named ones come back', () async {
    final adapter = RecordingAdapter(
      status: 200,
      body: {
        'pids': ['bk-B'],
      },
    );

    final removed = await clientOn(
      adapter,
    ).syncCatalogRemoved(['tr-A', 'bk-B', 'ep-C']);

    expect(removed, ['bk-B']);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, endsWith('/sync/catalog/removed'));
    expect(request.data, {
      'pids': ['tr-A', 'bk-B', 'ep-C'],
    });
  });

  test('nothing named is an empty list', () async {
    final removed = await clientOn(
      RecordingAdapter(status: 200, body: {'pids': <String>[]}),
    ).syncCatalogRemoved(['tr-A']);

    expect(removed, isEmpty);
  });

  test('a refusal is the structured error, whoever the server is', () async {
    final adapter = RecordingAdapter(
      status: 503,
      body: {'code': 'catalog-maintenance', 'message': 'the catalog is busy'},
    );

    await expectLater(
      clientOn(adapter).syncCatalogRemoved(['tr-A']),
      throwsA(
        isA<WaxDeckApiException>()
            .having((e) => e.statusCode, 'status', 503)
            .having((e) => e.code, 'code', 'catalog-maintenance'),
      ),
    );
  });
}
