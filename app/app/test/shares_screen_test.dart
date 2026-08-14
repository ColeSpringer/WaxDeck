import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/sharing/shares_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: routedHost(const SharesScreen()),
);

Finder _byId(String id) => find.bySemanticsIdentifier(id);

Share _share(
  String pid, {
  String targetTitle = 'Prancing Pony Blues',
  String targetKind = 'track',
  int plays = 7,
  bool allowDownload = false,
  DateTime? expiresAt,
}) => Share(
  pid: pid,
  url: '/s/SECRET-$pid',
  targetPid: 'tr-01JZX5N8QW3F4V9T2B7KDTARGET',
  targetKind: targetKind,
  targetTitle: targetTitle,
  allowDownload: allowDownload,
  createdAt: DateTime.utc(2026, 7, 1),
  expiresAt: expiresAt,
  plays: plays,
);

void main() {
  testWidgets('lists shares with target, kind, plays, and expiry', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..shares.addAll([
        // Noon UTC keeps the calendar date stable across the test
        // machine's timezone.
        _share('sh-1', expiresAt: DateTime.utc(2036, 8, 1, 12)),
        _share(
          'sh-2',
          targetTitle: 'Road Trip',
          targetKind: 'playlist',
          plays: 0,
        ),
      ]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('Prancing Pony Blues'), findsOneWidget);
    expect(find.text('track · 7 plays · expires Aug 1, 2036'), findsOneWidget);
    expect(find.text('Road Trip'), findsOneWidget);
    expect(find.text('playlist · 0 plays · never expires'), findsOneWidget);
  });

  testWidgets('a dead link says so rather than promising a date', (
    tester,
  ) async {
    final repo = FakeRepository()
      ..shares.addAll([
        _share('sh-1', expiresAt: DateTime.utc(2020, 1, 2, 12)),
      ]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(find.text('track · 7 plays · expired Jan 2, 2020'), findsOneWidget);
  });

  testWidgets('a downloadable link says what it hands out', (tester) async {
    final repo = FakeRepository()
      ..shares.addAll([_share('sh-1', allowDownload: true, plays: 1)]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    expect(
      find.text('track · 1 play · never expires · download allowed'),
      findsOneWidget,
    );
  });

  testWidgets('each medium is legible at a glance', (tester) async {
    final repo = FakeRepository()
      ..shares.addAll([
        _share('sh-1', targetKind: 'episode', targetTitle: 'Pipeweed'),
        _share('sh-2', targetKind: 'book', targetTitle: 'There And Back'),
        _share('sh-3', targetKind: 'playlist', targetTitle: 'Road Trip'),
      ]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    for (final glyph in <WaxGlyph>[
      WaxIcons.podcasts,
      WaxIcons.audiobooks,
      WaxIcons.playlists,
    ]) {
      expect(
        find.byWidgetPredicate(
          (widget) => widget is WaxIcon && widget.glyph == glyph,
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('revoking removes the share', (tester) async {
    final repo = FakeRepository()..shares.addAll([_share('sh-1')]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(_byId(SemanticsIds.shareRevoke('sh-1')));
    await tester.pumpAndSettle();

    expect(repo.revokeShareCalls, ['sh-1']);
    expect(_byId(SemanticsIds.shareRow('sh-1')), findsNothing);
    expect(_byId(SemanticsIds.sharesEmpty), findsOneWidget);
  });

  testWidgets('copy puts the absolute URL on the clipboard', (tester) async {
    final repo = FakeRepository()..shares.addAll([_share('sh-1')]);
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
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(_byId(SemanticsIds.shareCopy('sh-1')));
    await tester.pumpAndSettle();

    expect(copied.single, 'http://localhost:4420/s/SECRET-sh-1');
    expect(find.text('Link copied'), findsOneWidget);
  });
}
