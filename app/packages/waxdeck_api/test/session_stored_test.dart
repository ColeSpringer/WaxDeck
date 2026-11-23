import 'package:test/test.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

const _session = SessionState(
  authenticated: true,
  serverReadOnly: true,
  sessionId: 'se-01JZX5N8QW3F4V9T2B7KD3M9R6',
  user: WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
    username: 'listener',
    displayName: 'A Listener',
    roles: ['admin', 'user'],
    uploadEnabled: true,
    managePodcasts: true,
    canDelete: true,
  ),
);

/// A session a client keeps between launches reads back as the session it
/// was: who, role, rights, the server's switch and which session it is.
void main() {
  test('a session kept as text reads back equal, every field of it', () {
    final back = SessionState.fromStored(_session.toStored());

    expect(back, _session);
    expect(back?.user?.displayName, 'A Listener');
    expect(back?.user?.roles, ['admin', 'user']);
    expect(back?.user?.uploadEnabled, isTrue);
    expect(back?.user?.managePodcasts, isTrue);
    expect(back?.user?.canDelete, isTrue);
    expect(back?.serverReadOnly, isTrue);
    expect(back?.sessionId, 'se-01JZX5N8QW3F4V9T2B7KD3M9R6');
  });

  test('a session that names no user reads back so', () {
    const bare = SessionState(authenticated: true);
    expect(SessionState.fromStored(bare.toStored()), bare);
  });

  test('text that is no session reads as none', () {
    expect(SessionState.fromStored(''), isNull);
    expect(SessionState.fromStored('not json'), isNull);
    expect(SessionState.fromStored('[]'), isNull);
    expect(SessionState.fromStored('{"user":{}}'), isNull);
    expect(
      SessionState.fromStored('{"authenticated":true,"user":{"id":7}}'),
      isNull,
    );
  });
}
