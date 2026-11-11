import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

void main() {
  late RecordingAdapter adapter;
  late WaxDeckClient client;

  setUp(() {
    adapter = RecordingAdapter(status: 204);
    client = clientOn(adapter);
  });

  test(
    'a deletion hands the shared playlists over unless told otherwise',
    () async {
      await client.deleteUser('us-01JZX5N8QW3F4V9T2B7KDEXAMPLE');

      final request = adapter.requests.single;
      expect(request.method, 'DELETE');
      expect(
        request.uri.path,
        endsWith('/users/us-01JZX5N8QW3F4V9T2B7KDEXAMPLE'),
      );
      expect(request.uri.queryParameters['playlists'], 'transfer');
    },
  );

  test('a deletion can delete the playlists instead', () async {
    await client.deleteUser(
      'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
      playlists: 'delete',
    );

    expect(adapter.requests.single.uri.queryParameters['playlists'], 'delete');
  });
}
