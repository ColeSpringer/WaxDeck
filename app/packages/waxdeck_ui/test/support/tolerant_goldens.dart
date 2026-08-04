/// The comparator the CI goldens are checked with.
///
/// Alchemist's CI goldens obscure text so font rasterisation cannot make
/// them host-specific. Shape antialiasing is not text: rounded corners
/// disagree between graphics stacks, so compared exactly the suite is a
/// gate only the machine that baselined it can pass.
///
/// Both numbers are measured, from the nine goldens that disagreed
/// between the Ubuntu baseline and an Apple silicon host: nine tenths of
/// the disagreement was one channel off by 1/255, nothing above a delta
/// of 8 but the few pixels where a curve lands one over, and the worst
/// image differed by 0.034% once those were discounted. A one-pixel
/// spacing change still fails six goldens; a 16/255 colour shift, ten.
///
/// `goldens/linux/` is held to the exact comparison by path. It exists
/// to catch a wrong font weight, which is what host font rasterisation
/// also produces - no tolerance can tell those apart.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// About 3% of a channel: under a just-noticeable difference anywhere.
const int _channelTolerance = 8;

/// The share of an image that may differ by more than that before the
/// golden fails.
const double _pixelTolerance = 0.001;

/// Wraps whatever comparator the framework installed, so goldens are
/// still found and written where `--update-goldens` puts them.
void useTolerantGoldenComparator() {
  final installed = goldenFileComparator;
  if (installed is TolerantGoldenComparator) return;
  if (installed is! LocalFileComparator) return;
  goldenFileComparator = TolerantGoldenComparator(installed);
}

/// A [LocalFileComparator] that passes on host rasterisation noise and
/// fails on everything else.
class TolerantGoldenComparator extends LocalFileComparator {
  /// Everything but the verdict stays [strict]'s job: finding goldens,
  /// updating them, and writing the diff images beside a failure.
  TolerantGoldenComparator(this.strict) : super(_testFileIn(strict.basedir));

  final LocalFileComparator strict;

  /// [LocalFileComparator] takes the test *file* and keeps its
  /// directory, so a name inside the directory reconstructs it exactly.
  static Uri _testFileIn(Uri basedir) => basedir.resolve('golden_test.dart');

  /// The comparator is one per process, so without this the readable
  /// goldens would be relaxed along with the CI ones.
  static bool _tolerated(Uri golden) => golden.path.contains('/ci/');

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    if (!_tolerated(golden)) return strict.compare(imageBytes, golden);
    final List<int> master;
    try {
      master = await getGoldenBytes(golden);
    } on TestFailure {
      // No baseline yet; strict says so better than this could.
      return strict.compare(imageBytes, golden);
    }
    if (listEquals(imageBytes, master)) return true;
    final visible = await _visiblyDifferent(imageBytes, master);
    if (visible != null && visible <= _pixelTolerance) return true;
    return strict.compare(imageBytes, golden);
  }

  @override
  Future<void> update(Uri golden, Uint8List imageBytes) =>
      strict.update(golden, imageBytes);

  /// The share of pixels differing by more than [_channelTolerance] in
  /// any channel, or null when the two cannot be compared
  /// pixel-for-pixel.
  Future<double?> _visiblyDifferent(List<int> test, List<int> master) async {
    final a = await _pixels(master);
    final b = await _pixels(test);
    if (a == null || b == null || a.length != b.length) return null;
    var differing = 0;
    for (var i = 0; i < a.length; i += 4) {
      for (var channel = 0; channel < 4; channel++) {
        if ((a[i + channel] - b[i + channel]).abs() > _channelTolerance) {
          differing++;
          break;
        }
      }
    }
    return differing / (a.length / 4);
  }

  Future<Uint8List?> _pixels(List<int> png) async {
    final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData();
        return data?.buffer.asUint8List();
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
