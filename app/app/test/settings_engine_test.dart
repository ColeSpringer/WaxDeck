import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';
import 'routed_host.dart';

/// The settings the streaming engine serves read what the server says of
/// it: gone with a reason on a server without one, kept with the outage
/// said while it is away.
void main() {
  final en = AppLocalizationsEn();
  const none = ServerStreaming(configured: false, connected: false);
  const away = ServerStreaming(configured: true, connected: false);
  const up = ServerStreaming(
    configured: true,
    connected: true,
    timelines: true,
    voiceBoost: true,
    fileTools: true,
  );

  group('the gapless row', () {
    test('says the server has no engine', () {
      expect(webGaplessHelp(en, none, null), en.settingsWebGaplessNoEngine);
      // Whatever a mint said before: the server's word wins.
      expect(
        webGaplessHelp(en, none, 'feature-unavailable'),
        en.settingsWebGaplessNoEngine,
      );
    });

    test('says the engine is unreachable', () {
      expect(webGaplessHelp(en, away, null), en.settingsEngineUnreachable);
      expect(
        webGaplessHelp(en, away, 'transcode-limited'),
        en.settingsEngineUnreachable,
      );
    });

    test('says an engine that renders no queues renders none', () {
      const plain = ServerStreaming(configured: true, connected: true);
      expect(webGaplessHelp(en, plain, null), en.settingsWebGaplessUnavailable);
    });

    test('offers its switch unless nothing could be rendered', () {
      const plain = ServerStreaming(configured: true, connected: true);
      expect(webGaplessOffered(none), isFalse);
      expect(webGaplessOffered(plain), isFalse);
      // Away, the choice applies once the engine answers again.
      expect(webGaplessOffered(away), isTrue);
      expect(webGaplessOffered(up), isTrue);
      // A server too old to say keeps the switch.
      expect(webGaplessOffered(null), isTrue);
    });

    test('keeps the passing answers the server cannot give', () {
      expect(webGaplessHelp(en, up, null), en.settingsWebGaplessHelp);
      expect(
        webGaplessHelp(en, up, 'transcode-limited'),
        en.settingsWebGaplessBusy,
      );
      expect(
        webGaplessHelp(en, up, 'gapless-unsupported'),
        en.settingsWebGaplessBrowser,
      );
      expect(
        webGaplessHelp(en, up, 'gapless-format'),
        en.settingsWebGaplessFormat,
      );
      // A server too old to say keeps the row as it always read.
      expect(
        webGaplessHelp(en, null, 'feature-unavailable'),
        en.settingsWebGaplessUnavailable,
      );
    });
  });

  Future<void> pumpPlayback(WidgetTester tester, ServerStreaming? s) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeRepository(
      sessionState: const SessionState(
        authenticated: true,
        user: WaxDeckUser(id: 'us-2', username: 'sam'),
      ),
    )..serverStreaming = s;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
        child: routedHost(
          const SettingsSectionScreen(section: SettingsSection.playback),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder control(String id) =>
      find.bySemanticsIdentifier(SemanticsIds.setting(id));

  testWidgets('trimming and voice boost go, with the reason, without an '
      'engine', (tester) async {
    await pumpPlayback(tester, none);
    expect(control('trim-default'), findsNothing);
    expect(control('boost-default'), findsNothing);
    expect(find.text(en.settingsNeedsEngine), findsWidgets);
  });

  testWidgets('trimming and voice boost stay, saying the engine is away', (
    tester,
  ) async {
    await pumpPlayback(tester, away);
    expect(control('trim-default'), findsOneWidget);
    expect(control('boost-default'), findsOneWidget);
    expect(find.text(en.settingsEngineUnreachable), findsWidgets);
    expect(find.text(en.settingsNeedsEngine), findsNothing);
  });

  testWidgets('voice boost goes, saying why, from an engine that applies '
      'none', (tester) async {
    await pumpPlayback(
      tester,
      const ServerStreaming(
        configured: true,
        connected: true,
        timelines: true,
        fileTools: true,
      ),
    );
    expect(control('boost-default'), findsNothing);
    expect(control('trim-default'), findsOneWidget);
    expect(find.text(en.settingsEngineLacksThis), findsOneWidget);
  });

  testWidgets('trimming goes, saying why, from an engine that runs no '
      'analysis', (tester) async {
    await pumpPlayback(
      tester,
      const ServerStreaming(
        configured: true,
        connected: true,
        timelines: true,
        voiceBoost: true,
      ),
    );
    expect(control('trim-default'), findsNothing);
    expect(control('boost-default'), findsOneWidget);
    expect(find.text(en.settingsEngineLacksThis), findsOneWidget);
  });

  // What only a rendered queue or a transcode carries: crossfade and
  // levelling shape the queue the engine renders as one stream, and a
  // stream quality is a bitrate only the engine's transcode keeps to.
  // The test platform is a phone, which splits the quality by connection.
  const rendered = [
    'crossfade',
    'replay-gain',
    'stream-quality-wifi',
    'stream-quality-metered',
  ];

  testWidgets('crossfade, levelling and stream quality go, with the reason, '
      'without an engine', (tester) async {
    await pumpPlayback(tester, none);
    for (final id in rendered) {
      expect(control(id), findsNothing, reason: id);
    }
    // Trimming and voice boost say it too.
    expect(
      find.text(en.settingsNeedsEngine),
      findsNWidgets(2 + rendered.length),
    );
  });

  testWidgets('crossfade, levelling and stream quality stay, saying the '
      'engine is away', (tester) async {
    await pumpPlayback(tester, away);
    for (final id in rendered) {
      expect(control(id), findsOneWidget, reason: id);
    }
    expect(
      find.text(en.settingsEngineUnreachable),
      findsNWidgets(2 + rendered.length),
    );
  });

  testWidgets('crossfade and levelling go, saying why, from an engine that '
      'renders no queues', (tester) async {
    await pumpPlayback(
      tester,
      const ServerStreaming(
        configured: true,
        connected: true,
        voiceBoost: true,
        fileTools: true,
      ),
    );
    expect(control('crossfade'), findsNothing);
    expect(control('replay-gain'), findsNothing);
    expect(control('stream-quality-wifi'), findsOneWidget);
    expect(find.text(en.settingsEngineLacksThis), findsNWidgets(2));
  });

  testWidgets('trimming and voice boost read as ever with the engine up', (
    tester,
  ) async {
    await pumpPlayback(tester, up);
    expect(control('trim-default'), findsOneWidget);
    expect(control('boost-default'), findsOneWidget);
    expect(find.text(en.settingsTrimDefaultHelp), findsOneWidget);
    expect(find.text(en.settingsBoostDefaultHelp), findsOneWidget);
    expect(find.text(en.settingsEngineUnreachable), findsNothing);
  });
}
