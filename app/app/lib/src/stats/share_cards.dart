import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'share_card_export.dart';
import 'stats_controller.dart' show formatListenTime;

/// The platform's way of keeping a finished card.
final shareCardExporterProvider = Provider<ShareCardExporter>(
  (ref) => createShareCardExporter(),
);

/// The two shapes a recap card is cut to, both 1080 wide.
enum ShareCardFormat {
  story('Story', 'For a full-screen story', Size(1080, 1920)),
  square('Square', 'For a post or a message', Size(1080, 1080));

  const ShareCardFormat(this.label, this.blurb, this.size);

  final String label;
  final String blurb;
  final Size size;

  /// How many top artists the card has room for.
  int get artistCount => this == ShareCardFormat.story ? 5 : 3;
}

/// What one card says: the personal and server recaps draw the same
/// card from different shapes.
class ShareCardData {
  const ShareCardData({
    required this.year,
    required this.headline,
    required this.headlineLabel,
    required this.facts,
    required this.artists,
  });

  /// Everything a personal recap puts on a card.
  factory ShareCardData.personal(YearInReview recap) => ShareCardData(
    year: recap.year,
    headline: formatListenTime(recap.totalMs),
    headlineLabel: 'listened',
    facts: <(String, String)>[
      ('${recap.sessions}', 'sessions'),
      ('${recap.distinctItems}', 'different things'),
      ('${recap.longestStreakDays}', 'day streak'),
    ],
    artists: <String>[for (final entry in recap.topArtists) entry.name],
  );

  factory ShareCardData.server(ServerYearInReview recap) => ShareCardData(
    year: recap.year,
    headline: formatListenTime(recap.totalMs),
    headlineLabel: 'listened together',
    facts: <(String, String)>[
      ('${recap.participants}', 'listeners'),
      ('${recap.sessions}', 'sessions'),
    ],
    artists: <String>[for (final entry in recap.topArtists) entry.name],
  );

  final int year;

  /// The one number the card is about.
  final String headline;
  final String headlineLabel;

  /// The smaller numbers under it, value first.
  final List<(String, String)> facts;

  final List<String> artists;
}

/// Opens the card picker: both shapes drawn as they will export, each
/// with the verb that keeps it.
Future<void> showShareCardSheet(BuildContext context, ShareCardData data) {
  final colors = WaxColors.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface2,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ShareCardSheet(data: data),
  );
}

class _ShareCardSheet extends ConsumerStatefulWidget {
  const _ShareCardSheet({required this.data});

  final ShareCardData data;

  @override
  ConsumerState<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends ConsumerState<_ShareCardSheet> {
  /// One boundary per shape, inside the preview that paints it.
  final Map<ShareCardFormat, GlobalKey> _boundaries = {
    for (final format in ShareCardFormat.values) format: GlobalKey(),
  };

  /// The shape being exported right now, so its own button reads as
  /// busy while the other stays live.
  ShareCardFormat? _rendering;

  Future<void> _export(ShareCardFormat format) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final exporter = ref.read(shareCardExporterProvider);
    setState(() => _rendering = format);
    try {
      final png = await _renderPng(format);
      if (png == null) {
        messenger.show('The card could not be drawn');
        return;
      }
      final outcome = await exporter.export(
        png: png,
        fileName: 'waxdeck-${widget.data.year}-${format.name}.png',
        subject: 'My ${widget.data.year} in review',
      );
      messenger.show(switch (outcome) {
        ShareCardShared() => 'Card shared',
        ShareCardSaved(:final where) => 'Saved to $where',
        ShareCardFailed(:final reason) => reason,
      });
    } on Object {
      // A raster that would not encode, a platform directory that does
      // not exist: this is a button, and it has to say so rather than
      // going quiet and un-busying.
      messenger.show('The card could not be exported');
    } finally {
      if (mounted) setState(() => _rendering = null);
    }
  }

  /// Encodes the card the preview is already painting. The boundary
  /// sits inside the `FittedBox`, so its layer is the full 1080-wide
  /// card and the shrinking is a transform above it.
  Future<List<int>?> _renderPng(ShareCardFormat format) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return null;
    final object = _boundaries[format]?.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    // Ratio 1: the card is laid out at its own pixel dimensions, so
    // 1080 wide is 1080 wide on every device.
    final image = await object.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final exporter = ref.watch(shareCardExporterProvider);
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WaxSpace.s16,
            0,
            WaxSpace.s16,
            WaxSpace.s24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionHeader(
                title: 'Share cards',
                overline: 'Your year, cut to shape',
              ),
              if (!exporter.canExport)
                const WaxBanner(
                  message:
                      'This build cannot keep an image, so the cards are '
                      'preview only.',
                  tone: WaxBannerTone.caution,
                ),
              // A scrolled Row, not a ListView: the export captures a
              // painted boundary, and a lazy list paints no child that
              // is scrolled out. Unheighted, so text scale can grow it.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final format in ShareCardFormat.values)
                      Padding(
                        padding: const EdgeInsets.only(right: WaxSpace.s16),
                        child: _Preview(
                          format: format,
                          data: widget.data,
                          boundaryKey: _boundaries[format]!,
                          busy: _rendering == format,
                          onExport: exporter.canExport
                              ? () => _export(format)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: WaxSpace.s8),
              Text(
                'Cards are drawn here and never sent anywhere: what happens '
                'next is up to you.',
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One card as it will export, scaled to fit the sheet.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.format,
    required this.data,
    required this.boundaryKey,
    required this.busy,
    required this.onExport,
  });

  static const _height = 180.0;

  final ShareCardFormat format;
  final ShareCardData data;

  /// What the export captures: it wraps the card at its own layout
  /// size, inside the box that shrinks it.
  final GlobalKey boundaryKey;

  final bool busy;
  final VoidCallback? onExport;

  /// Wide enough for the verb under the narrowest card: a story is 101
  /// pixels wide here, with nowhere to put a label.
  static const _minWidth = 150.0;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final cardWidth = _height * format.size.width / format.size.height;
    final width = cardWidth < _minWidth ? _minWidth : cardWidth;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Center(
            child: Semantics(
              identifier: SemanticsIds.shareCardPreview(format.name),
              label: '${format.label} card, ${format.blurb.toLowerCase()}',
              excludeSemantics: true,
              child: ClipRRect(
                borderRadius: WaxRadius.card,
                child: SizedBox(
                  width: cardWidth,
                  height: _height,
                  // Drawn at its own size and scaled down, so the
                  // preview is the export rather than a lookalike.
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: YearShareCard(format: format, data: data),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: WaxSpace.s8),
          WaxButton(
            label: busy ? 'Drawing' : format.label,
            kind: WaxButtonKind.tonal,
            expand: true,
            semanticsId: SemanticsIds.shareCardExport(format.name),
            onPressed: busy ? null : onExport,
          ),
          Text(
            format.blurb,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: WaxType.caption.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// The card itself, at its export size. Tokens and text only: nothing is
/// fetched, so it renders the same offline and takes one frame.
class YearShareCard extends StatelessWidget {
  const YearShareCard({super.key, required this.format, required this.data});

  final ShareCardFormat format;
  final ShareCardData data;

  /// Everything on the card is sized against the 1080 the card is wide,
  /// so one set of proportions serves both shapes.
  static const _unit = 1080.0;

  double _s(double fraction) => _unit * fraction;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final story = format == ShareCardFormat.story;
    // Every size here is a fraction of 1080 in a box that cannot grow,
    // so the viewer's text scale would overflow the card it is baked
    // into. An exported image is not something they are reading.
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: format.size.width,
        height: format.size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colors.accentContainer,
                colors.canvas,
                colors.surface1,
              ],
              stops: const <double>[0, 0.55, 1],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(_s(story ? 0.08 : 0.07)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                WaxWordmark(size: _s(0.05), color: colors.textPrimary),
                const Spacer(),
                Text(
                  '${data.year}',
                  style: WaxType.display.copyWith(
                    fontSize: _s(story ? 0.16 : 0.13),
                    height: 1,
                    color: colors.accent,
                  ),
                ),
                SizedBox(height: _s(0.02)),
                Text(
                  data.headline,
                  style: WaxType.display.copyWith(
                    fontSize: _s(story ? 0.11 : 0.09),
                    height: 1.05,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  data.headlineLabel,
                  style: WaxType.titleEntity.copyWith(
                    fontSize: _s(0.035),
                    color: colors.textSecondary,
                  ),
                ),
                SizedBox(height: _s(0.05)),
                // Wrapped: four-digit numbers are wider than two-digit
                // ones and the canvas is fixed either way.
                Wrap(
                  spacing: _s(0.06),
                  runSpacing: _s(0.02),
                  children: <Widget>[
                    for (final (value, label) in data.facts)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: _s(0.4)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              value,
                              style: WaxType.titleEntity.copyWith(
                                fontSize: _s(0.05),
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              label,
                              style: WaxType.caption.copyWith(
                                fontSize: _s(0.022),
                                color: colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (data.artists.isNotEmpty) ...<Widget>[
                  SizedBox(height: _s(0.05)),
                  Text(
                    'MOST PLAYED',
                    style: WaxType.overline.copyWith(
                      fontSize: _s(0.022),
                      color: colors.textTertiary,
                    ),
                  ),
                  SizedBox(height: _s(0.015)),
                  for (final (index, artist)
                      in data.artists.take(format.artistCount).indexed)
                    Padding(
                      padding: EdgeInsets.only(bottom: _s(0.012)),
                      child: Row(
                        children: <Widget>[
                          SizedBox(
                            width: _s(0.06),
                            child: Text(
                              '${index + 1}',
                              style: WaxType.monoData.copyWith(
                                fontSize: _s(0.032),
                                color: colors.accent,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WaxType.titleItem.copyWith(
                                fontSize: _s(0.036),
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
