import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The one dialog three exports land in. What it owes them is the order
/// of its two closing acts: the copy has to reach the clipboard and the
/// modal has to be on its way out before the caller says so, because a
/// snackbar renders on the scaffold behind the dialog and nobody reads
/// it there. Two of the three had grown their own and one had lost that.

/// Records the pop, which is what "closes first" means: `Navigator.pop`
/// notifies its observers synchronously, while the route itself stays
/// mounted until its exit animation ends. Asserting the widget is gone
/// would be asserting on the animation.
class _PopWatch extends NavigatorObserver {
  bool popped = false;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped = true;
    super.didPop(route, previousRoute);
  }
}

void main() {
  const document = '#EXTM3U\n#EXTINF:214,Prancing Pony Blues\npony.flac\n';

  Future<_PopWatch> open(
    WidgetTester tester, {
    required VoidCallback onCopied,
  }) async {
    final pops = _PopWatch();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        navigatorObservers: <NavigatorObserver>[pops],
        home: Scaffold(
          body: Builder(
            builder: (context) => WaxButton(
              label: 'Export',
              onPressed: () => showDocumentDialog(
                context,
                title: 'Export M3U',
                document: document,
                closeLabel: 'Close',
                copyLabel: 'Copy',
                copySemanticsId: 'export-copy',
                onCopied: onCopied,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    return pops;
  }

  testWidgets('copies the document and closes before it reports', (
    tester,
  ) async {
    // No host for the platform channel in a widget test, so without a
    // mock the copy never completes and the dialog never closes.
    final copies = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copies.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );

    var reported = false;
    var poppedBeforeReporting = false;
    late final _PopWatch pops;
    pops = await open(
      tester,
      onCopied: () {
        reported = true;
        poppedBeforeReporting = pops.popped;
      },
    );

    expect(find.textContaining('Prancing Pony Blues'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('export-copy'));
    await tester.pumpAndSettle();

    expect(copies, <String>[document]);
    expect(reported, isTrue);
    expect(
      poppedBeforeReporting,
      isTrue,
      reason: 'the caller reports onto the scaffold, not behind the modal',
    );
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('closing reports nothing and copies nothing', (tester) async {
    final copies = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copies.add('x');
        return null;
      },
    );

    var reported = false;
    await open(tester, onCopied: () => reported = true);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(copies, isEmpty);
    expect(reported, isFalse);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
