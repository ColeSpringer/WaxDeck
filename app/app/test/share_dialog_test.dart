import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/sharing/share_dialog.dart';
import 'package:waxdeck/src/sharing/shares_controller.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_player_testing/waxdeck_player_testing.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'localized_host.dart';
import 'player_host.dart';
import 'routed_host.dart';

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

    // Share is a row of the player's one overflow menu now, not a
    // control of its own on the header.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.shareLink));
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
    expect(copied.single, 'http://server.test/s/FAKESECRET0');
    expect(shellMessageText(raisedMessage(tester)), 'Link copied');
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

    // Share is a row of the player's one overflow menu now, not a
    // control of its own on the header.
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.playerMore));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.shareLink));
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

  testWidgets('an episode with nothing to play through a link says so', (
    tester,
  ) async {
    // The server refuses a link to an episode it has not fetched whose
    // feed names no audio it relays. The generic conflict sentence
    // would tell the listener something else changed first.
    final repo = FakeRepository()
      ..shareError = const WaxDeckApiException(
        code: 'conflict',
        message:
            'this episode has no audio on the server and its feed names '
            'none to relay; fetch it first',
        statusCode: 409,
      );
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(
          Builder(
            builder: (context) => WaxButton(
              label: 'Share it',
              onPressed: () => showShareLinkDialog(context, pid: _episodePid),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share it'));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.shareCreate));
    await tester.pumpAndSettle();

    expect(repo.createShareCalls.single.pid, _episodePid);
    expect(
      shellMessageText(raisedMessage(tester)),
      'That episode has no audio a link could play: the server has not '
      'fetched any, and its feed offers none to stream. If the show has '
      'audio for it, fetch it first.',
    );
  });

  testWidgets('a link minted after the dialog was dismissed is still '
      'copied and listed', (tester) async {
    final gate = Completer<void>();
    final repo = FakeRepository(items: [testItem(_trackPid)])
      ..createShareGate = gate;
    final copied = _captureClipboard(tester);
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    // A shares screen left open behind the dialog.
    final listing = container.listen(sharesProvider, (_, _) {});
    addTearDown(listing.close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: routedHost(
          Builder(
            builder: (context) => WaxButton(
              label: 'Share it',
              onPressed: () => showShareLinkDialog(context, pid: _trackPid),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share it'));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.shareCreate));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ShareLinkDialog), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();

    final base = container.read(serverBaseUrlProvider);
    expect(copied, ['$base/s/FAKESECRET0']);
    expect(container.read(sharesProvider).value?.shares.map((s) => s.url), [
      '/s/FAKESECRET0',
    ]);
    expect(find.text('Share it'), findsOneWidget);
    expect(shellMessageText(raisedMessage(tester)), 'Link copied');
  });

  testWidgets('a link minted while the dialog is closing leaves the page '
      'under it', (tester) async {
    final gate = Completer<void>();
    final repo = FakeRepository(items: [testItem(_trackPid)])
      ..createShareGate = gate;
    _captureClipboard(tester);
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedHost(
          Builder(
            builder: (context) => WaxButton(
              label: 'Open',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => WaxButton(
                    label: 'Share it',
                    onPressed: () =>
                        showShareLinkDialog(context, pid: _trackPid),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share it'));
    await tester.pumpAndSettle();
    await tester.tap(_byId(SemanticsIds.shareCreate));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    // Still on its way out when the server answers.
    expect(find.byType(ShareLinkDialog), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(ShareLinkDialog), findsNothing);
    expect(find.text('Share it'), findsOneWidget);
  });
}
