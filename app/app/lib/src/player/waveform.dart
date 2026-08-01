import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// The peaks the music seek bar paints, or null when there are none.
///
/// Null is most of what this answers on a fresh server, and it is not a
/// loading state: the values come from the analyze pass, which nothing
/// runs automatically, so `pending` is what an unanalyzed library says
/// about every track. The seek bar draws its plain track for null and
/// never spins at it - `unavailable` is final, and `pending` only
/// changes when a pass runs, which is not something to poll for.
///
/// Auto-disposing per pid: the player holds one at a time, and coming
/// back to a track re-asks against the response's own ETag rather than
/// keeping a kilobyte of envelope per track played this session.
///
/// Who asks is the caller's decision, not this provider's. The music
/// face does. Podcast episodes are never analyzed, and a book's bar
/// spans a chapter rather than the file, so a full-file envelope under
/// it would be the wrong shape - both would get a truthful `unavailable`
/// or a misleading `ready`, and neither is worth the round trip.
final waveformProvider = FutureProvider.autoDispose
    .family<List<double>?, String>((ref, pid) async {
      try {
        return normalisedPeaks(
          await ref.watch(repositoryProvider).getWaveform(pid),
        );
      } on WaxDeckApiException {
        // A waveform is decoration. An item that has gone away, a catalog in
        // maintenance, or a credential that has just rotated all mean the
        // same thing here: draw the plain bar.
        return null;
      }
    });

/// [waveform] as heights from 0 to 1, or null when there is nothing to
/// draw.
///
/// Normalised against the track's own loudest bucket rather than full
/// scale, so a quiet master draws a shape instead of a flat line near
/// the axis. The stored values are absolute amplitude, and reading them
/// straight would make the envelope a loudness meter, which is not what
/// a seek bar is for.
///
/// [Waveform.resolution] is read rather than assumed: the catalog's 1000
/// buckets are a constant an analysis-version bump may change, and a
/// response whose two fields disagree is trusted for the values it
/// actually sent.
List<double>? normalisedPeaks(Waveform waveform) {
  if (!waveform.ready || waveform.peaks.isEmpty) return null;
  final buckets = waveform.resolution ?? waveform.peaks.length;
  final peaks = waveform.peaks.length > buckets
      ? waveform.peaks.sublist(0, buckets)
      : waveform.peaks;
  var loudest = 0;
  for (final peak in peaks) {
    if (peak > loudest) loudest = peak;
  }
  // Silence all the way through is a real answer for a corrupt or
  // digital-black file, and dividing by it is not.
  if (loudest <= 0) return null;
  return <double>[for (final peak in peaks) (peak / loudest).clamp(0.0, 1.0)];
}
