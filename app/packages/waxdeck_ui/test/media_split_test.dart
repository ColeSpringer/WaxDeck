import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// The segments a bar of [width] draws, as (left, width) pairs.
///
/// Read off a recording canvas rather than off a golden: the defect the
/// floor exists to prevent - a trailing share clipped to a smudge, or
/// dropped entirely - is a few pixels wide and reviews as a rendering
/// artefact. Numbers do not.
Future<List<({double left, double width})>> _segments(
  WidgetTester tester,
  List<MediaSplitSegment> segments, {
  double width = 260,
  TextDirection direction = TextDirection.ltr,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: direction,
      child: Theme(
        data: buildWaxTheme(variant: WaxThemeVariant.dark),
        child: Center(
          child: SizedBox(
            width: width,
            child: MediaSplitBar(segments: segments, summary: 'split'),
          ),
        ),
      ),
    ),
  );
  final painter = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byType(MediaSplitBar),
      matching: find.byType(CustomPaint),
    ),
  );
  final recorder = ui.PictureRecorder();
  final canvas = _RectCanvas(Canvas(recorder));
  painter.painter!.paint(canvas, Size(width, 10));
  recorder.endRecording().dispose();
  // The first rect is the track behind the shares.
  return canvas.rects.skip(1).toList();
}

/// Records the rounded rects a painter draws.
class _RectCanvas implements Canvas {
  _RectCanvas(this._inner);

  final Canvas _inner;
  final List<({double left, double width})> rects = [];

  @override
  void drawRRect(ui.RRect rrect, Paint paint) {
    rects.add((left: rrect.left, width: rrect.width));
    _inner.drawRRect(rrect, paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not recorded');
}

const _fourShares = <MediaSplitSegment>[
  MediaSplitSegment(label: 'Music', value: 24000000, domain: WaxDomain.music),
  MediaSplitSegment(
    label: 'Podcasts',
    value: 12000000,
    domain: WaxDomain.podcasts,
  ),
  MediaSplitSegment(
    label: 'Audiobooks',
    value: 6000000,
    domain: WaxDomain.audiobooks,
  ),
  MediaSplitSegment(label: 'Radio', value: 480000, domain: WaxDomain.radio),
];

void main() {
  testWidgets('every share is drawn, and the shares fill the bar', (
    tester,
  ) async {
    final drawn = await _segments(tester, _fourShares);
    expect(drawn, hasLength(4));
    // Nothing narrower than the bar's own height, which is the width a
    // pair of rounded ends needs to draw as a dot rather than a smudge.
    for (final rect in drawn) {
      expect(rect.width, greaterThanOrEqualTo(10));
    }
    // And the last share ends at the bar's edge: the floors and the
    // gaps come out of the width before the shares are measured, so
    // they still sum to it.
    final last = drawn.last;
    expect(last.left + last.width, closeTo(260, 0.01));
    // In order, with a gap between each pair.
    for (var i = 1; i < drawn.length; i++) {
      expect(drawn[i].left - (drawn[i - 1].left + drawn[i - 1].width), 3);
    }
  });

  testWidgets('a dominant share does not swallow the rest', (tester) async {
    // 200 hours of music against half an hour of radio: proportionally
    // the last two shares are a fraction of a pixel, and the bar has to
    // draw them anyway or the legend names four things the picture
    // shows two of.
    final drawn = await _segments(tester, const <MediaSplitSegment>[
      MediaSplitSegment(
        label: 'Music',
        value: 720000000,
        domain: WaxDomain.music,
      ),
      MediaSplitSegment(
        label: 'Podcasts',
        value: 10800000,
        domain: WaxDomain.podcasts,
      ),
      MediaSplitSegment(
        label: 'Audiobooks',
        value: 3600000,
        domain: WaxDomain.audiobooks,
      ),
      MediaSplitSegment(
        label: 'Radio',
        value: 1800000,
        domain: WaxDomain.radio,
      ),
    ], width: 328);
    expect(drawn, hasLength(4));
    for (final rect in drawn) {
      expect(rect.width, greaterThanOrEqualTo(10));
    }
    expect(drawn.last.left + drawn.last.width, closeTo(328, 0.01));
  });

  testWidgets('a bar too narrow for four floors still fits its box', (
    tester,
  ) async {
    // Below four floors plus three gaps the floor cannot be honoured;
    // proportions win, because a bar that overflows its box is worse
    // than a share drawn thin.
    final drawn = await _segments(tester, _fourShares, width: 40);
    expect(drawn, hasLength(4));
    expect(drawn.last.left + drawn.last.width, lessThanOrEqualTo(40.01));
  });

  testWidgets('an empty share is not drawn and an empty split is nothing', (
    tester,
  ) async {
    final drawn = await _segments(tester, const <MediaSplitSegment>[
      MediaSplitSegment(
        label: 'Music',
        value: 24000000,
        domain: WaxDomain.music,
      ),
      MediaSplitSegment(label: 'Radio', value: 0, domain: WaxDomain.radio),
    ]);
    expect(drawn, hasLength(1));

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Theme(
          data: buildWaxTheme(variant: WaxThemeVariant.dark),
          child: const MediaSplitBar(
            segments: <MediaSplitSegment>[],
            summary: 'nothing',
          ),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsNothing);
  });

  testWidgets('right to left, the first share leads from the reading edge', (
    tester,
  ) async {
    final drawn = await _segments(
      tester,
      _fourShares,
      direction: TextDirection.rtl,
    );
    expect(drawn, hasLength(4));
    // The largest share starts at the right edge and the rest march
    // leftward.
    expect(drawn.first.left + drawn.first.width, closeTo(260, 0.01));
    expect(drawn.last.left, closeTo(0, 0.01));
  });
}
