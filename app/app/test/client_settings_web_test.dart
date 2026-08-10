@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/settings/client_settings/browser_settings_store.dart';
import 'package:waxdeck/src/settings/client_settings/client_settings.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:web/web.dart' as web;

/// The one part of the per-device settings binding a VM suite cannot
/// reach: `_LocalStorage`, which hands [BrowserClientSettingsStore] the
/// real `window.localStorage`.
///
/// Everything above it - the probe, the fallback to memory, the
/// write-through shadow, the key semantics - is already tested on the VM
/// against a fake, a throwing one included (`test/client_settings_test.dart`).
/// What only a browser can answer is whether the binding underneath
/// stores anything at all, which is why this file goes through
/// [createClientSettingsStore] rather than constructing the store over a
/// stub: the conditional export is part of what is under test.
///
/// `@TestOn('browser')` is what keeps it out of the VM sweep: `flutter
/// test` skips it without compiling `package:web`. It sits in `test/`
/// like every other suite because a directory of its own does not work -
/// the browser runner's generated entrypoint cannot import across the
/// package's test root. `make test-app-chrome` and the CI step select it
/// by its `_web_test.dart` suffix.
void main() {
  const key = ClientSettingKeys.sidebarCollapsed;

  // Real storage outlives the test, and every case here starts from
  // nothing stored.
  void clear() => web.window.localStorage.removeItem(key);

  setUp(clear);
  tearDown(clear);

  test('the real binding round-trips through window.localStorage', () async {
    final store = createClientSettingsStore(null);

    // Not degraded is the assertion: the store probes at construction by
    // writing, reading back, and removing through the binding, and falls
    // back to memory if any of that fails. Passing means the real
    // localStorage answered.
    expect((store as BrowserClientSettingsStore).degraded, isFalse);

    await store.write(key, 'true');
    expect(web.window.localStorage.getItem(key), 'true');
  });

  test('a stored value outlives the store that wrote it', () async {
    await createClientSettingsStore(null).write(key, 'true');

    // A second store is what a reload is: its shadow is empty, so this
    // can only be answered out of localStorage itself.
    expect(await createClientSettingsStore(null).read(key), 'true');
  });

  test('a removal clears the browser key', () async {
    final store = createClientSettingsStore(null);
    await store.write(key, 'true');
    await store.remove(key);

    expect(web.window.localStorage.getItem(key), isNull);
    expect(await createClientSettingsStore(null).read(key), isNull);
  });
}
