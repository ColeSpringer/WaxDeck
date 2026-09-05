import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';

/// Full detail for one item, for the screens that want the technical
/// half of a release: the codec, the sample rate, the year.
///
/// Auto-disposing and per-pid: an album screen asks for exactly one of
/// these - the first track speaks for the release - and a listing that
/// asked per row would be a fetch per row for a caption.
///
/// A refusal is final, on [retryUnlessRefused]'s reasoning: the facts
/// sheet draws an error with a retry on it, and thirteen seconds of
/// invisible backoff before that error appears is a sheet that looks
/// broken while it works.
final itemDetailProvider = FutureProvider.autoDispose
    .family<ItemDetail, String>(
      (ref, pid) => ref.watch(repositoryProvider).getItem(pid),
      retry: retryUnlessRefused,
    );

/// An album's items in the order it was pressed.
///
/// A listing arrives in the catalog's own stable order, which is not
/// track order; disc and track number are what put a release back
/// together. Items carrying neither keep their arrival order behind the
/// ones that do, so a release with half its tags missing still reads as
/// a list rather than as a shuffle.
List<ItemSummary> albumOrder(List<ItemSummary> items) {
  final ordered = [...items];
  final arrival = {for (var i = 0; i < items.length; i++) items[i].pid: i};
  ordered.sort((a, b) {
    final numbered = (b.trackNumber != null ? 1 : 0).compareTo(
      a.trackNumber != null ? 1 : 0,
    );
    if (numbered != 0) return numbered;
    final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
    if (disc != 0) return disc;
    final track = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
    if (track != 0) return track;
    return (arrival[a.pid] ?? 0).compareTo(arrival[b.pid] ?? 0);
  });
  return ordered;
}

/// What an album screen can say about a release from its tracks alone.
class AlbumFacts {
  const AlbumFacts({
    required this.title,
    required this.artist,
    required this.caption,
  });

  /// Derives the header from the tracks themselves: there is no album
  /// endpoint to ask, and the rows carry everything a header shows.
  factory AlbumFacts.of(
    AppLocalizations l10n,
    WaxLocalizations wax,
    List<ItemSummary> tracks, {
    String? fallbackTitle,
  }) {
    final title =
        tracks.firstOrNull?.album ?? fallbackTitle ?? l10n.musicAlbumTitle;
    // A compilation has an artist per track and no one artist of its
    // own; saying the first track's name would be a small lie, so it
    // says what it is instead.
    final artists = {
      for (final t in tracks)
        if (t.artist != null) t.artist!,
    };
    final total = Duration(
      milliseconds: tracks.fold(0, (sum, t) => sum + t.durationMs),
    );
    return AlbumFacts(
      title: title,
      artist: switch (artists.length) {
        0 => null,
        1 => artists.first,
        _ => l10n.musicVariousArtists,
      },
      caption: [
        l10n.musicTrackCount(tracks.length),
        if (total > Duration.zero) formatRunningTime(wax, total),
      ].join(' · '),
    );
  }

  final String title;
  final String? artist;
  final String caption;
}

/// A duration as a listener talks about an album's length. The design
/// system's span words, elided a sleeve's way rather than a control's:
/// `formatSpan` says "1 min" for nothing and collapses past ten hours.
String formatRunningTime(WaxLocalizations l10n, Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return l10n.spanMinutes(minutes);
  if (minutes == 0) return l10n.spanHours(hours);
  return l10n.spanHoursMinutes(
    l10n.spanHours(hours),
    l10n.spanMinutes(minutes),
  );
}

/// "FLAC 44.1 kHz", the one line that says what this release actually
/// is. Uppercase codec because that is how the format is written
/// everywhere else it appears.
///
/// Either half can be missing, and the label is whatever is left rather
/// than a space where the other one would have been. Empty when both
/// are; the caller draws no chip for that.
String codecChipLabel(AppLocalizations l10n, ItemDetail detail) {
  final codec = (detail.codec ?? '').toUpperCase();
  final rate = detail.sampleRate;
  if (rate == null || rate <= 0) return codec;
  final khz = l10n.formatSampleRate(rate);
  return codec.isEmpty ? khz : '$codec $khz';
}
