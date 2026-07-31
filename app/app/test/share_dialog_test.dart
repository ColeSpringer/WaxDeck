import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';

import 'fakes.dart';
import 'player_host.dart';

const _trackPid = 'tr-01JZX5N8QW3F4V9T2B7KDSHARE1';
const _showPid = 'pc-01JZX5N8QW3F4V9T2B7KDSHOW01';
const _episodePid = 'tr-01JZX5N8QW3F4V9T2B7KDEP0001';

/// Captures clipboard writes; the platform channel has no host in
/// widget tests.
List<String> _captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add(
          (call.arguments as Map<Object?, Object?>)['text']! as String,
        );
      }
      return null;
    },
  );
  return copied;
}

Finder _byId(String id) => find.bySemanticsIdentifier(id);

void main() {
  testWidgets('creates a share with the chosen expiry and copies the URL', (
    tester,
  ) async {
    final repo = FakeRepository(items: [testItem(_trackPid)]);
    final engine = FakeEngine();
    final copied = _captureClipboard(tester);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testItem(_trackPid),
    );

    await tester.tap(find.byKey(const Key('share-link')));
    await tester.pumpAndSettle();
    // Music offers no start-at switch.
    expect(_byId(SemanticsIds.shareStartAt), findsNothing);

    await tester.tap(_byId(SemanticsIds.shareExpiry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 week').last);
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.shareAllowDownload));
    await tester.pumpAndSettle();

    await tester.tap(_byId(SemanticsIds.shareCreate));
    await tester.pumpAndSettle();

    expect(repo.createShareCalls, hasLength(1));
    expect(repo.createShareCalls.single, (
      pid: _trackPid,
      expiresInHours: 168,
      allowDownload: true,
      positionMs: null,
    ));
    expect(copied.single, 'http://localhost:4420/s/FAKESECRET0');
    expect(find.text('Link copied'), findsOneWidget);
    await harness.endPlayback(tester);
  });

  testWidgets('an episode share can start at the current position', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..addSubscription(testShow(_showPid))
      ..episodesByShow[_showPid] = [testEpisode(_episodePid)]
      ..playPositions[_episodePid] = 90000;
    final engine = FakeEngine(
      mediaDuration: const Duration(milliseconds: 214000),
    );
    final copied = _captureClipboard(tester);
    final harness = await pumpPlayer(
      tester,
      repo: repo,
      engine: engine,
      item: testEpisode(_episodePid),
    );

    // Play on a little: the offered start point is where the episode
    // stands when the sheet opens, not where it was when it started.
    engine.advance(const Duration(seconds: 5));
    await tester.pump();

    await tester.tap(find.byKey(const Key('share-link')));
    await tester.pumpAndSettle();

    expect(find.text('Start at 1:35'), findsOneWidget);
    await tester.tap(_byId(SemanticsIds.shareStartAt));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.shareCreate));
    await tester.pumpAndSettle();

    expect(repo.createShareCalls.single.pid, _episodePid);
    expect(repo.createShareCalls.single.positionMs, 95000);
    expect(repo.createShareCalls.single.expiresInHours, isNull);
    expect(copied, hasLength(1));
    await harness.endPlayback(tester);
  });
}
