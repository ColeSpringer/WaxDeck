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
/// Auto-disposing per pid: the player holds one at a time, rather than
/// keeping a kilobyte of envelope per track played this session. Note
/// that re-asking is a full re-read and not a revalidation - the
/// generated client sends no `If-None-Match` (only the artwork store
/// does) and dio carries no cache - so a surface that mounts and
/// unmounts repeatedly pays for each one. See `docs/deferred-work.md`.
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
          await ref.watch(trackWaveformProvider(pid).future),
        );
      } on WaxDeckApiException {
        // A waveform is decoration. An item that has gone away, a catalog in
        // maintenance, or a credential that has just rotated all mean the
        // same thing here: draw the plain bar. The refusal is still on
        // [trackWaveformProvider] for anything that has to tell "we could
        // not ask" from "there is nothing".
        return null;
      }
    });

/// The whole answer for one track, envelope and state together.
///
/// [waveformProvider] is derived from this rather than the other way
/// round, so both still cost one request per track, and the reason for
/// the split is what the peaks throw away. A null envelope conflates
/// three different things - `pending`, `unavailable`, and a request that
/// never landed - and anything deciding whether to *offer* a
/// peak-driven surface has to tell them apart. Greying a control out
/// because a connection dropped would take away something that would
/// have worked.
///
/// The error is left to surface as an error rather than being swallowed
/// into a null, for the same reason: `AsyncValue.hasError` is how a
/// caller sees "we could not ask" as distinct from "there is nothing".
///
/// And so it has to opt out of Riverpod 3's automatic retry, which
/// re-asks anything that fails with an `Exception` ten times across
/// about thirteen seconds. Two reasons, and the second is the one that
/// bites: a waveform is decoration and a refusal is not worth re-asking,
/// and a provider *between* retries reports `AsyncLoading` carrying the
/// previous error rather than `AsyncError` - so `.future` never settles,
/// and anything awaiting it, [waveformProvider] included, waits out the
/// whole backoff.
final trackWaveformProvider = FutureProvider.autoDispose
    .family<Waveform, String>(
      (ref, pid) async => ref.watch(repositoryProvider).getWaveform(pid),
      retry: (_, _) => null,
    );

/// Whether a peak-driven surface has anything to draw for [waveform].
///
/// A read still in flight, or one that failed, answers true: the caller
/// is deciding what to offer, and taking an option away on a dropped
/// connection is worse than offering one that turns out empty.
bool waveformMayHavePeaks(AsyncValue<Waveform> waveform) =>
    waveform.hasError ||
    !waveform.hasValue ||
    normalisedPeaks(waveform.requireValue) != null;

/// The peaks a book's seek bar paints across its whole timeline, or
/// null when there are none.
///
/// A separate family from [waveformProvider] because it is a different
/// question with a different answer, a different validator, and a
/// different cache entry: one part's envelope against every part's,
/// stitched by the server (`span=item`) so the duration weighting is
/// arithmetic done once rather than in every client.
///
/// A book's bar spans the book, so this is the only shape it can use.
/// The chapter view slices this rather than asking for a part: a part
/// is a file boundary and a chapter is not, and the two rarely line up.
final bookWaveformProvider = FutureProvider.autoDispose
    .family<List<double>?, String>((ref, pid) async {
      try {
        return normalisedPeaks(
          await ref.watch(repositoryProvider).getWaveform(pid, wholeItem: true),
        );
      } on WaxDeckApiException {
        // Decoration, as on the music face: draw the plain bar.
        return null;
      }
    });

/// The span of [peaks] between two fractions of the whole, keeping the
/// original normalisation.
///
/// Deliberately not renormalised. The chapter and book views are one
/// toggle apart, and rescaling a quiet chapter to fill the bar would
/// make the same audio look different depending on which button was
/// pressed last - and would tell a listener a whispered chapter is as
/// loud as the loudest thing in the book.
List<double>? slicePeaks(List<double>? peaks, double from, double to) {
  if (peaks == null || peaks.isEmpty) return null;
  if (!(from >= 0) || !(to <= 1) || to <= from) return null;
  final start = (from * peaks.length).floor().clamp(0, peaks.length - 1);
  final end = (to * peaks.length).ceil().clamp(start + 1, peaks.length);
  return peaks.sublist(start, end);
}

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
