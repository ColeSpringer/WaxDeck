// A share card on Android against the real waxdeck/share channel: the
// exporter writes the card into the one cache directory the FileProvider
// exposes and opens the system chooser over it. A driver outside this
// process sees each chooser open, checks it was granted the card, and
// dismisses it (e2e/tools/run-share-probe.sh, which the
// android-conformance workflow runs). Host tests mock the channel; only
// this runs the Kotlin half, the manifest provider and its path scope.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:waxdeck/src/stats/share_card_export.dart';

/// The name the driver looks for in the chooser's grant.
const _name = 'wax-share-probe.png';

/// How long a chooser gets to open and be dismissed. Generous: a human
/// pressing back also passes.
const _budget = Duration(minutes: 2);

/// Two one-pixel cards, apart in their bytes, so the second export can
/// be seen replacing the first.
final _cards = [
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGM4oaEBAALUARkFUI+kAAAAAElFTkSuQmCC',
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGPQ0DgBAAGUARn8OyyYAAAAAElFTkSuQmCC',
].map(base64Decode).toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a card shares through the chooser and replaces its last copy',
    () async {
      if (defaultTargetPlatform != TargetPlatform.android) {
        markTestSkipped('the waxdeck/share channel is Android-only');
        return;
      }
      final exporter = createShareCardExporter();
      final cards = Directory(
        p.join((await getTemporaryDirectory()).path, 'share-cards'),
      );
      for (final card in _cards) {
        final back = _backFromTheChooser();
        final outcome = await exporter.export(
          png: card,
          fileName: _name,
          subject: 'WaxDeck share probe',
        );
        expect(outcome, isA<ShareCardShared>());
        await back.timeout(_budget);
        final names = [
          for (final entry in cards.listSync()) p.basename(entry.path),
        ];
        expect(names, [_name], reason: 'one copy of the card, no temp file');
        expect(File(p.join(cards.path, _name)).readAsBytesSync(), card);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

/// Completes once the app leaves the foreground for the chooser and
/// comes back to it.
Future<void> _backFromTheChooser() {
  final done = Completer<void>();
  var left = false;
  late final AppLifecycleListener listener;
  listener = AppLifecycleListener(
    onStateChange: (state) {
      if (state != AppLifecycleState.resumed) {
        left = true;
      } else if (left && !done.isCompleted) {
        listener.dispose();
        done.complete();
      }
    },
  );
  return done.future;
}
