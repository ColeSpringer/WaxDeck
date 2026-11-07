import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/settings/integrations_sections.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'bundled_type.dart';
import 'fakes.dart';

/// A field's hint goes at the first keystroke, so it holds a format or
/// an example and nothing else, and on a phone it has to fit the lines
/// its field shows, in every language: a cut-off hint is lost text. What
/// a blank box means is said under the field instead, where it wraps and
/// stays.
void main() {
  setUpAll(loadBundledType);

  Future<void> pumpOnPhone(
    WidgetTester tester,
    FakeRepository repo,
    Widget child,
    Locale locale,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      Scaffold(body: ListView(children: [child])),
      container: appContainer(repo: repo),
      routed: false,
      locale: locale,
    );
  }

  /// Every hint on screen fits the lines its field gives it, in the
  /// bundled type. Answers the hints it read.
  List<String> expectHintsFit(WidgetTester tester) {
    final read = <String>[];
    final fields = find.byType(TextField);
    for (var i = 0; i < fields.evaluate().length; i++) {
      final field = fields.at(i);
      final hint = tester.widget<TextField>(field).decoration?.hintText;
      if (hint == null) continue;
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: field, matching: find.text(hint)),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '"$hint" is cut off at phone width',
      );
      read.add(hint);
    }
    return read;
  }

  const admin = WaxDeckUser(
    id: 'us-01JZX5N8QW3F4V9T2B7KDEXAMPLE',
    username: 'admin',
    roles: ['admin'],
  );

  // Every dialog in both languages; the literal copy is checked in en.
  for (final locale in const [Locale('en'), Locale('es')]) {
    final lang = locale.languageCode;
    final en = lang == 'en';

    testWidgets('the notification target editor, kind by kind ($lang)', (
      tester,
    ) async {
      await pumpOnPhone(
        tester,
        FakeRepository(),
        const PersonalNotificationTargetsSection(),
        locale,
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.notifyTargetAdd),
      );
      await tester.pumpAndSettle();

      final hints = <String>[];
      for (final kind in [
        'Pushover',
        'ntfy',
        'Gotify',
        'Discord',
        'Webhook',
        'Apprise',
        'UnifiedPush',
      ]) {
        await tester.tap(find.byKey(const Key('notify-target-kind')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(kind).last);
        await tester.pumpAndSettle();
        hints.addAll(expectHintsFit(tester));
        if (!en) continue;
        switch (kind) {
          case 'ntfy':
            expect(find.text('Empty uses ntfy.sh'), findsOneWidget);
          case 'Webhook':
            expect(
              find.text(
                'Receives a JSON object with event, title, body and timestamp',
              ),
              findsOneWidget,
            );
            expect(find.text('Empty sends posts unsigned'), findsOneWidget);
          case 'Apprise':
            expect(
              find.text("Empty uses the server's own configuration"),
              findsOneWidget,
            );
        }
      }
      // The formats that stay hints: the two priority ranges, the Discord
      // webhook, the headers and the Apprise targets.
      expect(hints, hasLength(5), reason: '$hints');
    });

    testWidgets('the ListenBrainz dialog ($lang)', (tester) async {
      await pumpOnPhone(
        tester,
        FakeRepository(),
        const ScrobblingSection(),
        locale,
      );
      await tester.tap(
        find.bySemanticsIdentifier(
          SemanticsIds.scrobblerConnect('listenbrainz'),
        ),
      );
      await tester.pumpAndSettle();
      expectHintsFit(tester);
      if (!en) return;
      expect(find.text('From your ListenBrainz profile page'), findsOneWidget);
      expect(find.text('Empty uses listenbrainz.org'), findsOneWidget);
    });

    testWidgets('the Last.fm credentials dialog ($lang)', (tester) async {
      final repo =
          FakeRepository(
              sessionState: const SessionState(
                authenticated: true,
                user: admin,
              ),
            )
            ..scrobblingConfig = const ScrobblingAdminConfig(
              lastfmConfigured: true,
              lastfmSource: 'settings',
              lastfmApiKey: 'key',
              lastfmSecretSet: true,
            );
      await pumpOnPhone(tester, repo, const ScrobblingSection(), locale);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.scrobblerSetupLastfm),
      );
      await tester.pumpAndSettle();
      expectHintsFit(tester);
      if (!en) return;
      expect(
        find.text('Register at last.fm/api/account/create'),
        findsOneWidget,
      );
      expect(find.text('Stored sealed; never shown again'), findsOneWidget);
    });

    testWidgets('the app password dialog ($lang)', (tester) async {
      await pumpOnPhone(
        tester,
        FakeRepository(),
        const AppPasswordsSection(),
        locale,
      );
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.appPasswordAdd));
      await tester.pumpAndSettle();
      expect(
        expectHintsFit(tester),
        en ? ['Which app is this for?'] : hasLength(1),
      );
    });

    testWidgets('the Discord application field ($lang)', (tester) async {
      await pumpOnPhone(
        tester,
        FakeRepository(),
        const DiscordPresenceSection(),
        locale,
      );
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.setting('discord-presence')),
      );
      await tester.pumpAndSettle();
      expect(expectHintsFit(tester), en ? ['Application ID'] : hasLength(1));
      if (!en) return;
      expect(find.text('Empty publishes as WaxDeck'), findsOneWidget);
    });
  }
}
