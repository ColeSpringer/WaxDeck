import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_es.dart';
import 'package:waxdeck/src/notifications/notifications_controller.dart';
import 'package:waxdeck/src/settings/notify_labels.dart';

/// The event names the spec says this server can emit.
///
/// The catalogue is a live read at runtime and a free string on the
/// wire, deliberately, so a newer server can add one; the spec's own
/// prose is the only machine-readable place the current set is written
/// down. Sliced rather than hand-copied, so adding an event to the
/// server without wording it here is this test failing rather than a row
/// that says `signup-requested` to somebody.
Set<String> _specCatalog() {
  final spec = File(_repoFile('api/openapi.yaml')).readAsStringSync();
  const opening = 'The current catalog is';
  final start = spec.indexOf(opening);
  if (start < 0) throw StateError('the spec no longer says "$opening"');
  final end = spec.indexOf('.', spec.indexOf('`playlist-synced`', start));
  if (end < 0) throw StateError('the catalog list no longer ends as it did');
  return RegExp(
    r'`([a-z][a-z-]*)`',
  ).allMatches(spec.substring(start, end)).map((m) => m.group(1)!).toSet();
}

/// A repo-relative path, resolved by walking up from `app/app`, which is
/// where this test runs.
String _repoFile(String relative) {
  var dir = Directory.current;
  for (var up = 0; up < 6; up++) {
    final candidate = File('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  throw StateError('no $relative above ${Directory.current.path}');
}

void main() {
  // Read once, and inside `main` rather than inside every test: a
  // failure here is the spec having moved, which every case below would
  // otherwise report separately.
  final catalog = _specCatalog();

  test('the spec still names the whole catalog', () {
    expect(catalog, hasLength(8));
  });

  for (final MapEntry(key: locale, value: l10n) in <String, AppLocalizations>{
    'en': AppLocalizationsEn(),
    'es': AppLocalizationsEs(),
  }.entries) {
    test('every catalog event has a title and a help in $locale', () {
      for (final token in catalog) {
        expect(
          notifyTokenTitle(l10n, token, ''),
          isNotEmpty,
          reason: '$token has no title in $locale',
        );
        expect(
          notifyTokenHelp(l10n, token, ''),
          isNotEmpty,
          reason: '$token has no help in $locale',
        );
      }
    });
  }

  // The inbox draws a row per event, and a row has to go somewhere. An
  // event with no kind falls back to the notifications screen, which is
  // the right answer for one a newer server invented and the wrong one
  // for an event this build ships knowing about.
  test('every catalog event has a destination', () {
    for (final token in catalog) {
      expect(
        NotificationKind.forEvent(token),
        isNotNull,
        reason: '$token has no kind, so its row would go nowhere in particular',
      );
    }
  });
}
