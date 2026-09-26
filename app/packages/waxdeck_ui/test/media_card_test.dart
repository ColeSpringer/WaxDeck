import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

void main() {
  testWidgets('the play affordance takes the verb its caller names', (
    tester,
  ) async {
    var plays = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWaxTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MediaCard(
              width: 160,
              data: const MediaTileData(title: 'Harbour FM'),
              onPlay: () => plays++,
              playLabel: 'Tune in Harbour FM',
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(ArtworkImage)));
    await tester.pumpAndSettle();

    // The card announces itself as one node, so the button is found by
    // the name it carries rather than through semantics.
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is WaxIconButton && widget.label == 'Tune in Harbour FM',
      ),
    );
    await tester.pump();
    expect(plays, 1);
  });
}
