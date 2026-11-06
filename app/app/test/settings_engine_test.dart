import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/settings/settings_registry.dart';
import 'package:waxdeck/src/settings/settings_section_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'bundled_type.dart';
import 'fakes.dart';
import 'routed_host.dart';

/// The settings the streaming engine serves read what the server says of
/// it: drawn disabled with the reason on a server without one, kept live
/// with the outage said while it is away. A reason several rows share is
/// one line under each group heading that holds one of them.
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
  // The three reasons a group line can give.
  final reasons = [
    en.settingsNeedsEngine,
    en.settingsEngineUnreachable,
    en.settingsEngineLacksThese,
  ];

  group('the gapless row', () {
    test('leaves no engine to its group line', () {
      expect(webGaplessHelp(en, none, null), isNull);
      // Whatever a mint said before: the server's word wins.
      expect(webGaplessHelp(en, none, 'feature-unavailable'), isNull);
    });

    test('leaves the unreachable engine to its group line', () {
      expect(webGaplessHelp(en, away, null), isNull);
      expect(webGaplessHelp(en, away, 'transcode-limited'), isNull);
    });

    test('leaves an engine that renders no queues to its group line', () {
      const plain = ServerStreaming(configured: true, connected: true);
      expect(webGaplessHelp(en, plain, null), isNull);
      expect(webGaplessHelp(en, plain, 'transcode-limited'), isNull);
    });

    test('offers its switch unless nothing could be rendered', () {
      // What the row reads: its rendered-queue need, through the engine
      // row every engine setting takes.
      bool offered(ServerStreaming? s) => engineRow(
        s,
        offers: (engine) => engine.timelines,
        lacking: en.settingsEngineLacksThis,
      ).offered;
      const plain = ServerStreaming(configured: true, connected: true);
      expect(offered(none), isFalse);
      expect(offered(plain), isFalse);
      // Away, the choice applies once the engine answers again.
      expect(offered(away), isTrue);
      expect(offered(up), isTrue);
      // A server too old to say keeps the switch.
      expect(offered(null), isTrue);
    });

    test('says nothing while it works, and keeps the refusals only the '
        'browser hears', () {
      expect(webGaplessHelp(en, up, null), isNull);
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

  Future<void> pumpPlayback(
    WidgetTester tester,
    ServerStreaming? s, {
    Size size = const Size(1000, 2400),
    String? setting,
  }) async {
    tester.view.physicalSize = size;
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
          SettingsSectionScreen(
            section: SettingsSection.playback,
            setting: setting,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder control(String id) =>
      find.bySemanticsIdentifier(SemanticsIds.setting(id));

  /// Whether the row's control is drawn but refuses a change, the way the
  /// card captions refuse one with no pointer.
  void expectDisabled(WidgetTester tester, String id) {
    expect(control(id), findsOneWidget, reason: id);
    final owner = tester.widget(
      find
          .ancestor(
            of: control(id),
            matching: find.byWidgetPredicate(
              (w) => w is WaxSwitch || w is WaxChoice<Object?>,
            ),
          )
          .first,
    );
    final onChanged = switch (owner) {
      WaxSwitch(:final onChanged) => onChanged,
      WaxChoice<Object?>(:final onChanged) => onChanged,
      _ => fail('$id is neither a switch nor a choice'),
    };
    expect(onChanged, isNull, reason: id);
  }

  /// The group a heading heads: the column its header opens.
  Finder groupOf(String heading) => find
      .ancestor(
        of: find.byWidgetPredicate(
          (w) => w is SectionHeader && w.title == heading,
        ),
        matching: find.byType(Column),
      )
      .first;

  /// [note] drawn once in [heading]'s group, between the heading and
  /// every one of [rows].
  void expectGroupNote(
    WidgetTester tester,
    String heading,
    String note,
    List<String> rows,
  ) {
    final line = find.descendant(
      of: groupOf(heading),
      matching: find.text(note),
    );
    expect(line, findsOneWidget, reason: heading);
    final header = find.byWidgetPredicate(
      (w) => w is SectionHeader && w.title == heading,
    );
    final at = tester.getRect(line);
    expect(
      at.top,
      greaterThanOrEqualTo(tester.getRect(header).bottom),
      reason: 'under the $heading heading',
    );
    for (final id in rows) {
      expect(
        at.bottom,
        lessThanOrEqualTo(tester.getRect(control(id)).top),
        reason: 'above $id',
      );
    }
  }

  /// No reason line anywhere in [heading]'s group.
  void expectNoGroupNote(String heading) {
    for (final reason in reasons) {
      expect(
        find.descendant(of: groupOf(heading), matching: find.text(reason)),
        findsNothing,
        reason: '$heading: $reason',
      );
    }
  }

  // The rows each engine group holds. The test platform is a phone,
  // which splits the stream quality by connection.
  const spoken = ['trim-default', 'boost-default'];
  const casting = ['crossfade', 'replay-gain'];
  const streamed = ['stream-quality-wifi', 'stream-quality-metered'];

  testWidgets('without an engine every engine row is disabled, and each of '
      'their groups says why once', (tester) async {
    await pumpPlayback(tester, none);
    for (final id in [...spoken, ...casting, ...streamed]) {
      expectDisabled(tester, id);
    }
    expectGroupNote(
      tester,
      en.settingsGroupSpokenWord,
      en.settingsNeedsEngine,
      spoken,
    );
    expectGroupNote(
      tester,
      en.settingsGroupCasting,
      en.settingsNeedsEngine,
      casting,
    );
    expectGroupNote(
      tester,
      en.settingsGroupStreaming,
      en.settingsNeedsEngine,
      streamed,
    );
    expect(find.text(en.settingsNeedsEngine), findsNWidgets(3));
    // A group with no engine row says nothing of it.
    expectNoGroupNote(en.settingsGroupPlayer);
  });

  testWidgets('an engine away keeps every row live, and each of their '
      'groups says it is away', (tester) async {
    await pumpPlayback(tester, away);
    for (final id in [...spoken, ...casting, ...streamed]) {
      expect(control(id), findsOneWidget, reason: id);
    }
    expectGroupNote(
      tester,
      en.settingsGroupSpokenWord,
      en.settingsEngineUnreachable,
      spoken,
    );
    expectGroupNote(
      tester,
      en.settingsGroupCasting,
      en.settingsEngineUnreachable,
      casting,
    );
    expectGroupNote(
      tester,
      en.settingsGroupStreaming,
      en.settingsEngineUnreachable,
      streamed,
    );
    expect(find.text(en.settingsNeedsEngine), findsNothing);
  });

  testWidgets('voice boost alone is disabled, saying why on its own row', (
    tester,
  ) async {
    await pumpPlayback(
      tester,
      const ServerStreaming(
        configured: true,
        connected: true,
        timelines: true,
        fileTools: true,
      ),
    );
    expectDisabled(tester, 'boost-default');
    expect(control('trim-default'), findsOneWidget);
    expect(find.text(en.settingsEngineLacksThis), findsOneWidget);
    expectNoGroupNote(en.settingsGroupSpokenWord);
  });

  testWidgets('trimming alone is disabled, saying why on its own row', (
    tester,
  ) async {
    await pumpPlayback(
      tester,
      const ServerStreaming(
        configured: true,
        connected: true,
        timelines: true,
        voiceBoost: true,
      ),
    );
    expectDisabled(tester, 'trim-default');
    expect(control('boost-default'), findsOneWidget);
    expect(find.text(en.settingsEngineLacksThis), findsOneWidget);
    expectNoGroupNote(en.settingsGroupSpokenWord);
  });

  testWidgets('an engine that renders no queues disables crossfade and '
      'levelling, said once under their heading', (tester) async {
    await pumpPlayback(
      tester,
      const ServerStreaming(
        configured: true,
        connected: true,
        voiceBoost: true,
        fileTools: true,
      ),
    );
    expectDisabled(tester, 'crossfade');
    expectDisabled(tester, 'replay-gain');
    expect(control('stream-quality-wifi'), findsOneWidget);
    expectGroupNote(
      tester,
      en.settingsGroupCasting,
      en.settingsEngineLacksThese,
      casting,
    );
    expect(find.text(en.settingsEngineLacksThese), findsOneWidget);
    expect(find.text(en.settingsEngineLacksThis), findsNothing);
    expectNoGroupNote(en.settingsGroupSpokenWord);
    expectNoGroupNote(en.settingsGroupStreaming);
  });

  testWidgets('a reason shared across groups is said in each group it '
      'touches, and only there', (tester) async {
    // No analysis and no rendered queues: trimming in one group,
    // crossfade and levelling in another; voice boost works.
    await pumpPlayback(
      tester,
      const ServerStreaming(
        configured: true,
        connected: true,
        voiceBoost: true,
      ),
    );
    expectDisabled(tester, 'trim-default');
    expectGroupNote(
      tester,
      en.settingsGroupSpokenWord,
      en.settingsEngineLacksThese,
      spoken,
    );
    expectGroupNote(
      tester,
      en.settingsGroupCasting,
      en.settingsEngineLacksThese,
      casting,
    );
    expectNoGroupNote(en.settingsGroupStreaming);
    expect(find.text(en.settingsEngineLacksThis), findsNothing);
  });

  testWidgets('trimming and voice boost read as ever with the engine up', (
    tester,
  ) async {
    await pumpPlayback(tester, up);
    expect(control('trim-default'), findsOneWidget);
    expect(control('boost-default'), findsOneWidget);
    // The labels carry them: no line under a switch that works.
    for (final reason in reasons) {
      expect(find.text(reason), findsNothing, reason: reason);
    }
  });

  // A settings search opens the section scrolled to the row, centred;
  // on a phone the section's top is then screens away, so the reason
  // has to be within the row's own group to be read at all.
  group('a search landing on a disabled row at phone width', () {
    /// Lands on [id] in a [size] window and checks the row and the reason
    /// line of its group are both on screen.
    Future<void> expectLanding(
      WidgetTester tester,
      String id, {
      Size size = const Size(390, 844),
    }) async {
      await pumpPlayback(tester, none, size: size, setting: id);
      // The landing follows the row for as long as it is marked.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      final top = WaxScaffold.barHeight(
        tester.element(find.byType(SettingsSectionScreen)),
        largeTitle: false,
      );
      bool inView(Rect r) => r.top >= top && r.bottom <= size.height;

      final row = tester.getRect(control(id));
      expect(inView(row), isTrue, reason: 'the landing shows $id: $row');
      final notes = find.text(en.settingsNeedsEngine);
      final above = [
        for (var i = 0; i < notes.evaluate().length; i++)
          tester.getRect(notes.at(i)),
      ].where((r) => r.bottom <= row.top).toList();
      expect(above, isNotEmpty, reason: 'a reason line above $id');
      final nearest = above.reduce((a, b) => a.bottom > b.bottom ? a : b);
      expect(
        inView(nearest),
        isTrue,
        reason: 'its group line is on screen: $nearest, view from $top',
      );
    }

    for (final id in [...spoken, ...casting, ...streamed]) {
      testWidgets('on $id shows its group line', (tester) async {
        await expectLanding(tester, id);
      });
    }

    // Large type on a small phone puts the line furthest from a row the
    // landing centres. Drawn in the bundled type, which is what a reader
    // sees at that size: the test font's glyphs are twice as wide. At 2.0
    // replay-gain is the deepest row a test platform draws; 3.0 puts its
    // line as far up as web-gapless, one row lower and web only, has it
    // at 2.0.
    for (final scale in const <double>[2, 3]) {
      testWidgets('on replay-gain at $scale text scale on a small phone '
          'shows its group line', (tester) async {
        await tester.runAsync(loadBundledType);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await expectLanding(tester, 'replay-gain', size: const Size(360, 640));
      });
    }
  });
}
