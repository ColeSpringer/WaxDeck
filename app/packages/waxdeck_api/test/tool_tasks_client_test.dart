import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

void main() {
  late RecordingAdapter adapter;
  late WaxDeckClient client;

  setUp(() {
    adapter = RecordingAdapter();
    client = clientOn(adapter);
  });

  test('a clear-finished sweep names its own scope by default', () async {
    adapter.enqueue(200, {'deleted': 3, 'kept': 0});

    final cleared = await client.clearFinishedToolTasks();

    expect(cleared.deleted, 3);
    expect(cleared.kept, 0);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, endsWith('/tools/tasks/clear-finished'));
    expect(request.data, {'scope': 'mine'});
  });

  test('everyone\'s sweep names the wide scope, and what it kept', () async {
    adapter.enqueue(200, {'deleted': 7, 'kept': 1});

    final cleared = await client.clearFinishedToolTasks(all: true);

    expect(cleared.deleted, 7);
    expect(cleared.kept, 1);
    expect(adapter.requests.single.data, {'scope': 'all'});
  });

  test('a member\'s wide sweep is refused as forbidden', () async {
    adapter.enqueue(403, {
      'code': 'forbidden',
      'message': 'administrators only',
    });

    await expectLater(
      client.clearFinishedToolTasks(all: true),
      throwsA(
        isA<WaxDeckApiException>().having((e) => e.code, 'code', 'forbidden'),
      ),
    );
  });
}
