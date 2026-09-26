import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/downloads/download_notices.dart';
import 'package:waxdeck/src/l10n/off_tree.dart';
import 'package:waxdeck/src/sync/sync_providers.dart';

import 'fakes.dart';
import 'localized_host.dart';

void main() {
  Future<FakeDownloads> pump(WidgetTester tester) async {
    final downloads = FakeDownloads();
    addTearDown(downloads.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [downloadManagerProvider.overrideWithValue(downloads)],
        child: localizedHost(
          const DownloadNoticeRationale(child: SizedBox.expand()),
        ),
      ),
    );
    return downloads;
  }

  testWidgets('says why before the OS asks again', (tester) async {
    final downloads = await pump(tester);

    downloads.explainNotifications();
    await tester.pumpAndSettle();
    expect(find.text('Show download progress?'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();

    expect(downloads.notificationRequests, 1);
    expect(find.text('Show download progress?'), findsNothing);
  });

  testWidgets('not now asks nothing', (tester) async {
    final downloads = await pump(tester);

    downloads.explainNotifications();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(downloads.notificationRequests, 0);
  });

  test('the notices speak the app language', () {
    final copy = downloadCopy(l10nFor(const [Locale('es')]));

    expect(copy.downloading('{progress}'), 'Descargando {progress}');
    expect(copy.part('El hobbit', 3, 20), 'El hobbit (3 de 20)');
    expect(copy.downloaded, 'Descargado');
  });
}
