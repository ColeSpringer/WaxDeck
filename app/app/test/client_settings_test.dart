import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/search/search_controller.dart';
import 'package:waxdeck/src/settings/client_settings/browser_settings_store.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/settings/client_settings_providers.dart';
import 'package:waxdeck/src/settings/prefs_controller.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';

/// A browser's storage, as far as this store is concerned. The knobs are
/// the ways a real one fails: refusing writes when it is out of room,
/// refusing everything in a partitioned context, and the one that a
/// write-only probe would miss - taking a write and then answering null.
class FakeBrowserStorage implements BrowserStorage {
  FakeBrowserStorage({
    this.throwOnWrite = false,
    this.throwOnRead = false,
    this.swallowWrites = false,
  });

  final Map<String, String> values = {};
  bool throwOnWrite;
  bool throwOnRead;

  /// Accepts a write and keeps nothing.
  final bool swallowWrites;

  @override
  String? getItem(String key) {
    if (throwOnRead) throw StateError('storage is not readable here');
    return values[key];
  }

  @override
  void setItem(String key, String value) {
    if (throwOnWrite) throw StateError('quota exceeded');
    if (swallowWrites) return;
    values[key] = value;
  }

  @override
  void removeItem(String key) {
    if (throwOnWrite) throw StateError('quota exceeded');
    values.remove(key);
  }
}

/// A store that breaks the port's never-throw promise, for the failure
/// the mixin guards against rather than trusts.
class ThrowingClientSettingsStore implements ClientSettingsStore {
  @override
  Future<String?> read(String key) async => throw StateError('no reads');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('no writes');

  @override
  Future<void> remove(String key) async => throw StateError('no removals');
}

/// A store that refuses writes to one key. The shape a real one fails
/// in: a mirror locked by another connection, a quota reached partway
/// through a launch.
class PickyClientSettingsStore implements ClientSettingsStore {
  PickyClientSettingsStore(this.refuse);

  /// The key whose writes throw. Everything else behaves.
  final String refuse;

  final MemoryClientSettingsStore _kept = MemoryClientSettingsStore();

  @override
  Future<String?> read(String key) => _kept.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (key == refuse) throw StateError('cannot write $key');
    await _kept.write(key, value);
  }

  @override
  Future<void> remove(String key) => _kept.remove(key);
}

/// A preference whose decode throws, which is the other way a stored
/// value can take a launch down.
class ExplodingSetting extends Notifier<String> with StoredSetting<String> {
  static const key = 'waxdeck.test.exploding';

  @override
  String get settingKey => key;

  @override
  String get defaultValue => 'default';

  @override
  String? decode(String raw) => throw const FormatException('unparseable');

  @override
  String encode(String value) => value;

  @override
  String build() => hydrate();
}

final explodingSettingProvider = NotifierProvider<ExplodingSetting, String>(
  ExplodingSetting.new,
);

void main() {
  group('BrowserClientSettingsStore', () {
    test('a working browser holds a value across store instances', () async {
      final storage = FakeBrowserStorage();
      await BrowserClientSettingsStore(storage).write('k', 'v');
      // A second store is the next launch: nothing carries over but the
      // browser's own storage.
      final relaunched = BrowserClientSettingsStore(storage);
      expect(relaunched.degraded, isFalse);
      expect(await relaunched.read('k'), 'v');
    });

    test('an unset key reads null', () async {
      expect(
        await BrowserClientSettingsStore(FakeBrowserStorage()).read('k'),
        isNull,
      );
    });

    test('a removed key is unset again', () async {
      final storage = FakeBrowserStorage();
      final store = BrowserClientSettingsStore(storage);
      await store.write('k', 'v');
      await store.remove('k');
      expect(await store.read('k'), isNull);
      expect(storage.values.containsKey('k'), isFalse);
    });

    test('the probe leaves nothing behind', () {
      final storage = FakeBrowserStorage();
      BrowserClientSettingsStore(storage);
      expect(storage.values, isEmpty);
    });

    test('a browser that refuses writes degrades to memory instead of '
        'throwing', () async {
      final store = BrowserClientSettingsStore(
        FakeBrowserStorage(throwOnWrite: true),
      );
      expect(store.degraded, isTrue);
      // The preference still holds for the session, which is the whole
      // point: a private window gets a working app, not a broken one.
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
    });

    test('a browser that refuses reads degrades too', () async {
      final store = BrowserClientSettingsStore(
        FakeBrowserStorage(throwOnRead: true),
      );
      expect(store.degraded, isTrue);
      expect(await store.read('k'), isNull);
    });

    test('storage that accepts a write and keeps nothing fails the '
        'probe', () async {
      // A write-only probe would call this working and then hand back a
      // store whose reads silently answer null forever.
      final store = BrowserClientSettingsStore(
        FakeBrowserStorage(swallowWrites: true),
      );
      expect(store.degraded, isTrue);
    });

    test('a write that fails mid-session still answers for the '
        'session', () async {
      final storage = FakeBrowserStorage();
      final store = BrowserClientSettingsStore(storage);
      await store.write('k', 'first');
      // The quota fills up after the probe passed, which is the ordinary
      // way this happens.
      storage.throwOnWrite = true;
      await store.write('k', 'second');
      // Not 'first': what this session set is the freshest value there
      // is, whether or not the browser agreed to hold it.
      expect(await store.read('k'), 'second');
      expect(storage.values['k'], 'first');
    });

    test('a read that starts failing mid-session answers null, not an '
        'exception', () async {
      final storage = FakeBrowserStorage();
      final store = BrowserClientSettingsStore(storage);
      storage.values['k'] = 'v';
      storage.throwOnRead = true;
      expect(await store.read('k'), isNull);
    });

    test('a removal the browser refuses still reads as removed', () async {
      // The mirror of the failed-write case, and the one a shadow that
      // only held values would get wrong: the key is gone from memory,
      // so a value-shaped shadow falls through to storage and answers
      // with exactly the value that was just deleted.
      final storage = FakeBrowserStorage();
      final store = BrowserClientSettingsStore(storage);
      await store.write('k', 'v');
      storage.throwOnWrite = true;
      await store.remove('k');
      expect(await store.read('k'), isNull);
      // Still in the browser, which is honest - it comes back next
      // launch - and not what this session is told.
      expect(storage.values['k'], 'v');
    });

    test('a key removed and then set again reads as set', () async {
      final storage = FakeBrowserStorage();
      final store = BrowserClientSettingsStore(storage);
      await store.write('k', 'first');
      await store.remove('k');
      await store.write('k', 'second');
      expect(await store.read('k'), 'second');
    });
  });

  group('stored preferences', () {
    ProviderContainer containerOver(ClientSettingsStore store) {
      final container = ProviderContainer(
        overrides: [clientSettingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the sidebar starts expanded and collapses once the store '
        'answers', () async {
      final store = MemoryClientSettingsStore();
      await store.write(ClientSettingKeys.sidebarCollapsed, 'true');
      final container = containerOver(store);

      // The first frame does not wait on a disk.
      expect(container.read(sidebarCollapsedProvider), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sidebarCollapsedProvider), isTrue);
    });

    test('a toggle is written and read back by the next launch', () async {
      final store = MemoryClientSettingsStore();
      final first = containerOver(store);
      first.read(sidebarCollapsedProvider.notifier).toggle();
      expect(first.read(sidebarCollapsedProvider), isTrue);

      final next = containerOver(store);
      expect(next.read(sidebarCollapsedProvider), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(next.read(sidebarCollapsedProvider), isTrue);
    });

    test('a toggle made before the read lands is not undone by it', () async {
      final store = MemoryClientSettingsStore();
      await store.write(ClientSettingKeys.sidebarCollapsed, 'true');
      final container = containerOver(store);

      // Collapsed on disk, opened by hand while the read is in flight:
      // the listener's own action is the newer of the two.
      container.read(sidebarCollapsedProvider.notifier).toggle();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sidebarCollapsedProvider), isTrue);
      container.read(sidebarCollapsedProvider.notifier).toggle();
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sidebarCollapsedProvider), isFalse);
    });

    test('a stored value that does not parse reads as nothing '
        'stored', () async {
      final store = MemoryClientSettingsStore();
      await store.write(ClientSettingKeys.sidebarCollapsed, 'perhaps');
      await store.write(ClientSettingKeys.recentSearches, 'not json');
      final container = containerOver(store);

      expect(container.read(sidebarCollapsedProvider), isFalse);
      expect(container.read(recentSearchesProvider), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sidebarCollapsedProvider), isFalse);
      expect(container.read(recentSearchesProvider), isEmpty);
    });

    test('recent searches survive a launch, newest first', () async {
      final store = MemoryClientSettingsStore();
      final first = containerOver(store);
      first.read(recentSearchesProvider.notifier).remember('nightjar');
      first.read(recentSearchesProvider.notifier).remember('kind of blue');

      final next = containerOver(store);
      // Read before the settle, not after: providers are lazy, so
      // nothing has asked the store anything until something reads.
      expect(next.read(recentSearchesProvider), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(next.read(recentSearchesProvider), <String>[
        'kind of blue',
        'nightjar',
      ]);
    });

    test('forgetting one is remembered too', () async {
      final store = MemoryClientSettingsStore();
      final first = containerOver(store);
      first.read(recentSearchesProvider.notifier).remember('nightjar');
      first.read(recentSearchesProvider.notifier).forget('nightjar');

      final next = containerOver(store);
      expect(next.read(recentSearchesProvider), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(next.read(recentSearchesProvider), isEmpty);
    });

    test('a stored list longer than the limit is trimmed on read', () async {
      // An older build with a larger limit, or a hand-edited value.
      final store = MemoryClientSettingsStore();
      await store.write(
        ClientSettingKeys.recentSearches,
        '["a","b","c","d","e","f","g","h","i","j","k","l"]',
      );
      final container = containerOver(store);

      expect(container.read(recentSearchesProvider), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(recentSearchesProvider),
        hasLength(RecentSearches.limit),
      );
    });

    test('a store that will not hold anything costs the preference, not '
        'the app', () async {
      // The degraded web store, seen from the reader's side.
      final store = BrowserClientSettingsStore(
        FakeBrowserStorage(throwOnWrite: true),
      );
      final container = containerOver(store);
      container.read(sidebarCollapsedProvider.notifier).toggle();
      expect(container.read(sidebarCollapsedProvider), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sidebarCollapsedProvider), isTrue);
    });

    test('a store that breaks its own contract is still not a crash at '
        'startup', () async {
      // Both shipped stores promise never to throw. These are unawaited
      // futures on a launch path, though, so one that did would be an
      // unhandled zone error rather than a caught failure - and the
      // whole cost of losing here is a preference read at its default.
      final container = containerOver(ThrowingClientSettingsStore());

      expect(container.read(sidebarCollapsedProvider), isFalse);
      container.read(sidebarCollapsedProvider.notifier).toggle();
      expect(container.read(sidebarCollapsedProvider), isTrue);
      // Two turns: one for the read the build started, one for the
      // write the toggle handed off.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sidebarCollapsedProvider), isTrue);
    });

    test('a rebuild keeps the preference rather than reverting to the '
        'default', () async {
      // Riverpod re-runs build on the same notifier instance when a
      // dependency changes, and whatever build returns replaces the
      // state. A hydrate that always answered defaultValue would discard
      // the listener's preference and, because the value had already
      // been touched, never read it back either - the setting would sit
      // at its default for the rest of the session.
      final store = MemoryClientSettingsStore();
      final container = containerOver(store);

      container.read(sidebarCollapsedProvider.notifier).toggle();
      expect(container.read(sidebarCollapsedProvider), isTrue);

      container.invalidate(sidebarCollapsedProvider);
      expect(container.read(sidebarCollapsedProvider), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sidebarCollapsedProvider), isTrue);
    });

    test('a hydrated preference also survives a rebuild', () async {
      final store = MemoryClientSettingsStore();
      await store.write(ClientSettingKeys.sidebarCollapsed, 'true');
      final container = containerOver(store);

      expect(container.read(sidebarCollapsedProvider), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(sidebarCollapsedProvider), isTrue);

      container.invalidate(sidebarCollapsedProvider);
      expect(container.read(sidebarCollapsedProvider), isTrue);
    });

    test('a search remembered before the stored list arrives does not '
        'erase it', () async {
      // The base rule - what this session set wins - is right for a
      // preference naming one thing and a permanent data loss for one
      // that accumulates: the write that follows would persist a
      // one-entry history over everything that was there. Recent
      // searches merge instead.
      final store = MemoryClientSettingsStore();
      await store.write(
        ClientSettingKeys.recentSearches,
        '["kind of blue","nightjar"]',
      );
      final container = containerOver(store);

      // Reading builds the notifier and starts the load; remembering
      // before the next microtask is the race.
      expect(container.read(recentSearchesProvider), isEmpty);
      container.read(recentSearchesProvider.notifier).remember('mogwai');
      await Future<void>.delayed(Duration.zero);

      expect(container.read(recentSearchesProvider), <String>[
        'mogwai',
        'kind of blue',
        'nightjar',
      ]);
      // And the merged list is what the next launch reads, not the
      // one-entry list the racing write left behind.
      expect(
        await store.read(ClientSettingKeys.recentSearches),
        '["mogwai","kind of blue","nightjar"]',
      );
    });

    test('a stored list holding two casings of one query collapses on '
        'read', () async {
      // Reachable from an older build or a hand-edited value. The list
      // has one invariant and everything that builds one applies it, so
      // a value out of storage obeys it as surely as one just typed.
      final store = MemoryClientSettingsStore();
      await store.write(
        ClientSettingKeys.recentSearches,
        '["Nightjar","nightjar","mogwai"]',
      );
      final container = containerOver(store);

      expect(container.read(recentSearchesProvider), isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(recentSearchesProvider), <String>[
        'Nightjar',
        'mogwai',
      ]);
    });

    test('a decode that throws reads as nothing stored', () async {
      // decode is written per setting, so the mixin enforces the
      // "anything that does not parse reads as unset" promise rather
      // than trusting every future implementation of it to.
      final store = MemoryClientSettingsStore();
      await store.write(ExplodingSetting.key, 'anything');
      final container = containerOver(store);

      expect(container.read(explodingSettingProvider), 'default');
      await Future<void>.delayed(Duration.zero);
      expect(container.read(explodingSettingProvider), 'default');
    });
  });

  group('adopting the account theme', () {
    const user = WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']);

    ProviderContainer over(
      ClientSettingsStore store,
      ThemePref? account, {
      bool signedIn = true,
    }) {
      final repo = FakeRepository()
        ..sessionState = SessionState(
          authenticated: signedIn,
          user: signedIn ? user : null,
        )
        ..prefs = Prefs(theme: account);
      final container = ProviderContainer(
        overrides: [
          clientSettingsStoreProvider.overrideWithValue(store),
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// A launch: build the notifier, let the document and the store
    /// answer, and say what the theme came out as.
    Future<ThemePref> launch(
      ClientSettingsStore store,
      ThemePref? account,
    ) async {
      final container = over(store, account);
      // Listened, not read: the notifier has to still be alive when the
      // document lands, which is the rebuild the adoption rides.
      container.listen(themeSettingProvider, (_, _) {});
      await container.read(prefsControllerProvider.future);
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return container.read(themeSettingProvider);
    }

    test(
      'a device with nothing of its own takes what the account had',
      () async {
        // The upgrade this exists for: somebody deliberately chose OLED
        // back when the theme was the account's, and the build that made
        // it per-device must not silently return them to the system's.
        final store = MemoryClientSettingsStore();

        expect(await launch(store, ThemePref.oled), ThemePref.oled);
        expect(await store.read(ClientSettingKeys.theme), 'oled');
        expect(await store.read(ClientSettingKeys.themeAdopted), isNotNull);
      },
    );

    test('a device that already chose keeps its own', () async {
      final store = MemoryClientSettingsStore();
      await store.write(ClientSettingKeys.theme, 'dark');

      expect(await launch(store, ThemePref.light), ThemePref.dark);
      expect(await store.read(ClientSettingKeys.theme), 'dark');
    });

    test('an account theme set after the first launch is not taken', () async {
      // The whole point of the move, and the failure a device found:
      // the first launch had nothing to adopt, so with only an
      // in-memory guard the question was asked again next launch - and
      // a `light` set from another client retook a phone that had
      // never been told to follow the account.
      final store = MemoryClientSettingsStore();

      expect(await launch(store, null), ThemePref.system);
      expect(await store.read(ClientSettingKeys.themeAdopted), isNotNull);

      expect(
        await launch(store, ThemePref.light),
        ThemePref.system,
        reason: 'the account stopped deciding at the first launch',
      );
      expect(await store.read(ClientSettingKeys.theme), isNull);
    });

    test('a signed-out launch does not spend the question', () async {
      // Signed out the document is the empty default, not the account's.
      // Marking the question answered there would drop the theme of
      // everybody who installs the app and signs in after - which is
      // every fresh install of the build that moved the setting.
      final store = MemoryClientSettingsStore();
      final signedOut = over(store, null, signedIn: false);
      signedOut.listen(themeSettingProvider, (_, _) {});
      await signedOut.read(prefsControllerProvider.future);
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(await store.read(ClientSettingKeys.themeAdopted), isNull);

      expect(await launch(store, ThemePref.oled), ThemePref.oled);
    });

    test('signing in takes the account theme, not the document it '
        'replaces', () async {
      // The failure a device found. Riverpod keeps a provider's previous
      // value while it reloads, so for the frames just after signing in
      // the document is the signed-out empty one with `hasValue` true.
      // Reading the theme there answers null, and the question is spent:
      // the marker lands, nothing is taken, and the listener's `light`
      // is gone for good.
      final store = MemoryClientSettingsStore();
      final container = over(store, ThemePref.light, signedIn: false);
      container.listen(themeSettingProvider, (_, _) {});
      await container.read(prefsControllerProvider.future);
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      await container
          .read(authControllerProvider.notifier)
          .login(username: 'admin', password: 'wax');
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(container.read(themeSettingProvider), ThemePref.light);
      expect(await store.read(ClientSettingKeys.theme), 'light');
    });

    test('a theme that will not store leaves the question open', () async {
      // The mark is what makes this unrepeatable, so it must not outlive
      // a failed write of the theme it records. Marked first, a store
      // that drops the value at launch would lose a deliberate OLED for
      // good; this way the next launch asks again.
      final store = PickyClientSettingsStore(ClientSettingKeys.theme);

      expect(await launch(store, ThemePref.oled), ThemePref.system);
      expect(await store.read(ClientSettingKeys.themeAdopted), isNull);
    });

    test('a taken theme is not taken again after being changed back', () async {
      // Adopt OLED, then set the system back by hand. The account still
      // says OLED, and the next launch must leave the newer choice
      // alone.
      final store = MemoryClientSettingsStore();
      expect(await launch(store, ThemePref.oled), ThemePref.oled);

      await store.write(ClientSettingKeys.theme, 'system');

      expect(await launch(store, ThemePref.oled), ThemePref.system);
    });
  });

  group('signing out', () {
    ProviderContainer signedIn(ClientSettingsStore store) {
      final container = ProviderContainer(
        overrides: [
          clientSettingsStoreProvider.overrideWithValue(store),
          repositoryProvider.overrideWithValue(FakeRepository()),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
          audioEngineProvider.overrideWithValue(FakeEngine()),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('forgets the recent searches and keeps the rest', () async {
      // The one key in this store that is the departing account's
      // content rather than the machine's: the strings name things in
      // their library, and on web they sit in origin-scoped storage that
      // the next account on this browser reads back.
      final store = MemoryClientSettingsStore();
      await store.write(ClientSettingKeys.sidebarCollapsed, 'true');
      final container = signedIn(store);
      container.read(recentSearchesProvider.notifier).remember('nightjar');
      await Future<void>.delayed(Duration.zero);
      expect(
        store.read(ClientSettingKeys.recentSearches),
        completion('["nightjar"]'),
      );

      await container.read(authControllerProvider.notifier).signOutLocally();

      expect(await store.read(ClientSettingKeys.recentSearches), isNull);
      expect(container.read(recentSearchesProvider), isEmpty);
      // The rail describes this machine, and stands.
      expect(await store.read(ClientSettingKeys.sidebarCollapsed), 'true');
    });

    test('a history that will not clear cannot strand the sign-out', () async {
      // Same rule the queue follows: a session left standing is a dead
      // credential the UI keeps using, which is worse than a stale key.
      final container = signedIn(ThrowingClientSettingsStore());

      await container.read(authControllerProvider.notifier).signOutLocally();

      expect(
        container.read(authControllerProvider).value!.authenticated,
        isFalse,
      );
    });
  });
}
