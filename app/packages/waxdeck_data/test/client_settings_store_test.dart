import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_data/waxdeck_data.dart';

void main() {
  group('DriftClientSettingsStore', () {
    late MirrorDatabase db;
    late ClientSettingsStore store;

    setUp(() {
      db = inMemoryMirrorDatabase();
      store = DriftClientSettingsStore(db);
    });
    tearDown(() => db.close());

    test('an unset key reads null, so the caller keeps its default', () async {
      expect(await store.read(ClientSettingKeys.sidebarCollapsed), isNull);
    });

    test('a write is what the next read answers', () async {
      await store.write(ClientSettingKeys.sidebarCollapsed, 'true');
      expect(await store.read(ClientSettingKeys.sidebarCollapsed), 'true');
    });

    test('a second write replaces rather than duplicating', () async {
      await store.write(ClientSettingKeys.recentSearches, '["a"]');
      await store.write(ClientSettingKeys.recentSearches, '["b","a"]');
      expect(await store.read(ClientSettingKeys.recentSearches), '["b","a"]');
      expect(await db.select(db.clientSettings).get(), hasLength(1));
    });

    test('keys do not read each other', () async {
      await store.write(ClientSettingKeys.sidebarCollapsed, 'true');
      expect(await store.read(ClientSettingKeys.recentSearches), isNull);
    });

    test('a removed key is unset again, not empty', () async {
      await store.write(ClientSettingKeys.sidebarCollapsed, 'true');
      await store.remove(ClientSettingKeys.sidebarCollapsed);
      expect(await store.read(ClientSettingKeys.sidebarCollapsed), isNull);
    });

    test('removing a key that was never set is not an error', () async {
      await store.remove(ClientSettingKeys.recentSearches);
      expect(await store.read(ClientSettingKeys.recentSearches), isNull);
    });

    test('a database that is gone costs the preference, not the '
        'caller', () async {
      // The port promises never to throw, and this is the
      // implementation that has a real way to: a closed database, a
      // locked file, a full disk. Its callers are an unawaited startup
      // read and a button, neither of which has anywhere to put an
      // exception.
      await db.close();
      expect(await store.read(ClientSettingKeys.sidebarCollapsed), isNull);
      await expectLater(
        store.write(ClientSettingKeys.sidebarCollapsed, 'true'),
        completes,
      );
      await expectLater(
        store.remove(ClientSettingKeys.sidebarCollapsed),
        completes,
      );
    });
  });

  group('MemoryClientSettingsStore', () {
    test('behaves like the durable one within a session', () async {
      final store = MemoryClientSettingsStore();
      expect(await store.read('k'), isNull);
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
      await store.remove('k');
      expect(await store.read('k'), isNull);
    });
  });
}
