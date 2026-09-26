import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/prefs_controller.dart';
import 'l10n.dart';

/// The device's languages, most preferred first, written by the app's
/// root ([SystemLocalesObserver]): a provider cannot hear them change.
class SystemLocales extends Notifier<List<Locale>> {
  @override
  List<Locale> build() => PlatformDispatcher.instance.locales;

  set locales(List<Locale> value) => state = value;
}

final systemLocalesProvider = NotifierProvider<SystemLocales, List<Locale>>(
  SystemLocales.new,
);

/// The app's copy in [locales] as `MaterialApp` would resolve them,
/// English when none is one this build has.
AppLocalizations l10nFor(List<Locale> locales) => lookupAppLocalizations(
  basicLocaleListResolution(locales, appSupportedLocales),
);

/// The app's copy for what is drawn outside the element tree: the
/// Android Auto folders, the media session, the tray menu, the download
/// notifications. Resolved as the tree's is, so the two never disagree.
final offTreeL10nProvider = Provider<AppLocalizations>((ref) {
  final chosen = ref.watch(localeOverrideProvider);
  if (chosen != null) return lookupAppLocalizations(chosen);
  return l10nFor(ref.watch(systemLocalesProvider));
});

/// Writes the device's languages into [systemLocalesProvider] as the
/// platform changes them.
class SystemLocalesObserver extends ConsumerStatefulWidget {
  const SystemLocalesObserver({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SystemLocalesObserver> createState() =>
      _SystemLocalesObserverState();
}

class _SystemLocalesObserverState extends ConsumerState<SystemLocalesObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    ref.read(systemLocalesProvider.notifier).locales =
        locales ?? const <Locale>[];
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
