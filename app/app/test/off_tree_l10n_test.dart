import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/off_tree.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

ProviderContainer _container({required List<Locale> system, String? stored}) {
  final repo = FakeRepository(
    sessionState: const SessionState(
      authenticated: true,
      user: WaxDeckUser(id: 'us-1', username: 'admin', roles: ['admin']),
    ),
  );
  if (stored != null) repo.prefs = Prefs(locale: stored);
  final container = ProviderContainer(
    overrides: [repositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  container.read(systemLocalesProvider.notifier).locales = system;
  return container;
}

void main() {
  test('follows the device while nothing is stored', () {
    final container = _container(system: const [Locale('es', 'MX')]);

    expect(container.read(offTreeL10nProvider).localeName, 'es');
  });

  test('a device language this build lacks resolves to English', () {
    final container = _container(
      system: const [Locale('fr', 'FR'), Locale('de')],
    );

    expect(container.read(offTreeL10nProvider).localeName, 'en');
  });

  test('the stored choice outranks the device once it loads', () async {
    final container = _container(
      system: const [Locale('en', 'US')],
      stored: 'es',
    );
    final seen = <String>[];
    container.listen(
      offTreeL10nProvider,
      (_, next) => seen.add(next.localeName),
      fireImmediately: true,
    );

    await pumpEventQueue();

    expect(seen, <String>['en', 'es']);
  });

  test('a change of device language is followed', () {
    final container = _container(system: const [Locale('en')]);
    expect(container.read(offTreeL10nProvider).localeName, 'en');

    container.read(systemLocalesProvider.notifier).locales = const [
      Locale('es'),
    ];

    expect(container.read(offTreeL10nProvider).localeName, 'es');
  });
}
