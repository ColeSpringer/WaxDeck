import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'support/recording_adapter.dart';

const _user = {
  'id': 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
  'username': 'listener',
  'roles': ['user'],
  'uploadEnabled': false,
};

void main() {
  late RecordingAdapter adapter;
  late WaxDeckClient client;

  setUp(() {
    adapter = RecordingAdapter();
    client = clientOn(adapter);
  });

  test('a session carries the server\'s read-only state', () async {
    adapter.enqueue(200, {
      'authenticated': true,
      'user': _user,
      'csrfToken': 'csrf-1',
      'server': {'readOnly': true},
    });
    expect((await client.getSession()).serverReadOnly, isTrue);

    adapter.enqueue(200, {
      'authenticated': true,
      'user': _user,
      'csrfToken': 'csrf-1',
      'server': {'readOnly': false},
    });
    expect((await client.getSession()).serverReadOnly, isFalse);
  });

  test('a server that says nothing is not read-only', () async {
    // The `server` object is optional and a signed-out probe carries none.
    adapter.enqueue(200, {'authenticated': true, 'user': _user});
    expect((await client.getSession()).serverReadOnly, isFalse);

    adapter.enqueue(200, {'authenticated': false});
    expect((await client.getSession()).serverReadOnly, isFalse);
  });
}
