import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../media_view.dart';

/// The split bar over its legend, largest share first, or null when at
/// most one medium has time on it. Zero shares go before the count: a
/// listen with no time still gets a slice on the wire.
MediaSplitBar? mediaSplitBar(
  AppLocalizations l10n,
  List<MediaTypeListening> byMediaType, {
  Key? key,
}) {
  final shares = <MediaTypeListening>[
    for (final m in byMediaType)
      if (m.ms > 0) m,
  ];
  if (shares.length < 2) return null;
  String labelOf(StatsMediaType type) => switch (type) {
    StatsMediaType.music => l10n.statsMediaMusic,
    StatsMediaType.podcast => l10n.statsMediaPodcasts,
    StatsMediaType.audiobook => l10n.statsMediaAudiobooks,
    StatsMediaType.radio => l10n.statsMediaRadio,
  };
  return MediaSplitBar(
    key: key,
    summary: l10n.statsSplitSummary(
      <String>[
        for (final m in shares)
          l10n.statsSplitShare(
            labelOf(m.mediaType),
            l10n.formatListenTime(m.ms),
          ),
      ].join(', '),
    ),
    segments: <MediaSplitSegment>[
      for (final m in shares)
        MediaSplitSegment(
          label: labelOf(m.mediaType),
          // Sized from milliseconds, so a share in days and one in
          // minutes compare without either being rounded away first.
          value: m.ms,
          valueLabel: l10n.formatListenTime(m.ms),
          domain: waxDomainOfStats(m.mediaType),
        ),
    ],
  );
}
