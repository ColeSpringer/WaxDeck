import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/sharing/shares_screen.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

Widget _host(FakeRepository repo) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(repo)],
  child: const MaterialApp(home: SharesScreen()),
);

Share _share(
  String pid, {
  String targetTitle = 'Prancing Pony Blues',
  String targetKind = 'track',
  int plays = 7,
  DateTime? expiresAt,
}) => Share(
  pid: pid,
  url: '/s/SECRET-$pid',
  targetPid: 'tr-01JZX5N8QW3F4V9T2B7KDTARGET',
  targetKind: targetKind,
  targetTitle: targetTitle,
  allowDownload: false,
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
        _share('sh-1', expiresAt: DateTime.utc(2026, 8, 1, 12)),
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
    expect(find.text('track | 7 plays | expires 2026-08-01'), findsOneWidget);
    expect(find.text('Road Trip'), findsOneWidget);
    expect(find.text('playlist | 0 plays | never expires'), findsOneWidget);
  });

  testWidgets('an album share shows the album icon', (tester) async {
    final repo = FakeRepository()
      ..shares.addAll([
        _share('sh-1', targetKind: 'album', targetTitle: 'Signal Garden'),
      ]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    // Distinct from a track's note icon, so album shares are legible.
    expect(find.byIcon(Icons.album), findsOneWidget);
    expect(find.byIcon(Icons.music_note), findsNothing);
  });

  testWidgets('revoking removes the share', (tester) async {
    final repo = FakeRepository()..shares.addAll([_share('sh-1')]);
    await tester.pumpWidget(_host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('share-revoke-sh-1')));
    await tester.pumpAndSettle();

    expect(repo.revokeShareCalls, ['sh-1']);
    expect(find.byKey(const Key('share-row-sh-1')), findsNothing);
    expect(find.text('No share links yet'), findsOneWidget);
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

    await tester.tap(find.byKey(const Key('share-copy-sh-1')));
    await tester.pumpAndSettle();

    expect(copied.single, 'http://localhost:4420/s/SECRET-sh-1');
    expect(find.text('Link copied'), findsOneWidget);
  });
}
