import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../artwork/artwork_providers.dart';
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
    artists: <ShareCardArtist>[
      for (final entry in recap.topArtists)
        (name: entry.name, artUrl: entry.artUrl),
    ],
  );

  factory ShareCardData.server(ServerYearInReview recap) => ShareCardData(
    year: recap.year,
    headline: formatListenTime(recap.totalMs),
    headlineLabel: 'listened together',
    facts: <(String, String)>[
      ('${recap.participants}', 'listeners'),
      ('${recap.sessions}', 'sessions'),
    ],
    artists: <ShareCardArtist>[
      for (final entry in recap.topArtists)
        (name: entry.name, artUrl: entry.artUrl),
    ],
  );

  final int year;

  /// The one number the card is about.
  final String headline;
  final String headlineLabel;

  /// The smaller numbers under it, value first.
  final List<(String, String)> facts;

  final List<ShareCardArtist> artists;
}

/// One name on the MOST PLAYED list, and where its cover lives.
///
/// The URL rides the card's data because it is already on the wire and
/// was being dropped; whether it turns into a picture is decided later,
/// by whoever has an artwork store and a frame to spare.
typedef ShareCardArtist = ({String name, String? artUrl});

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

  /// The covers, by artist name, once they are fetched AND decoded.
  var _covers = const <String, ImageProvider>{};

  /// The fetch, so an export that beats it can wait rather than
  /// exporting a card whose pictures were a frame away.
  Future<void>? _fetchingCovers;

  @override
  void initState() {
    super.initState();
    // On open, not on export: the preview is the export, so a card with
    // covers has to be showing them before anybody presses anything.
    _fetchingCovers = _fetchCovers();
  }

  /// Fetches and decodes the covers the cards will draw.
  ///
  /// The decode is the half that matters. `_renderPng` captures one
  /// frame, so an `ImageProvider` handed to the tree undecoded paints
  /// nothing in that frame and the card exports with holes in it; the
  /// future is not finished until `precacheImage` has each one in the
  /// image cache, and only then does the tree hear about them.
  Future<void> _fetchCovers() async {
    final store = ref.read(artworkStoreProvider);
    // The widest card decides: the story shape lists five.
    final wanted = <ShareCardArtist>[
      ...widget.data.artists.take(
        ShareCardFormat.values
            .map((f) => f.artistCount)
            .reduce((a, b) => a > b ? a : b),
      ),
    ];
    final found = <String, ImageProvider>{};
    for (final artist in wanted) {
      final url = artist.artUrl;
      if (url == null || url.isEmpty) continue;
      try {
        final bytes = await store.bytesFor(url, _coverPx);
        if (bytes == null || !mounted) continue;
        final provider = MemoryImage(bytes);
        // The error callback rather than the surrounding catch, because
        // precacheImage does not throw: it completes its future either
        // way and hands a decode failure to FlutterError.onError. Bytes
        // that will not decode - a proxy's HTML error page, a truncated
        // response - would otherwise be recorded as found and drawn as
        // a blank square, which is the hole in the card this whole path
        // exists to prevent.
        var decoded = true;
        await precacheImage(
          provider,
          context,
          onError: (_, _) => decoded = false,
        );
        if (!decoded) continue;
        found[artist.name] = provider;
      } on Object {
        // A cover that will not fetch or will not decode is a monogram,
        // which is a designed state rather than a failure: the card is
        // one frame with no network in it, and it always renders.
      }
    }
    if (!mounted || found.isEmpty) return;
    setState(() => _covers = found);
  }

  /// The rung a cover is fetched at. The card draws it at 4.5% of 1080
  /// - 49 pixels - so this is the smallest rung that cannot look soft.
  static const _coverPx = 128;

  Future<void> _export(ShareCardFormat format) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    final exporter = ref.read(shareCardExporterProvider);
    setState(() => _rendering = format);
    try {
      // Bounded, because offline honesty beats a spinner that never
      // ends: a card with monograms is the designed state, and waiting
      // forever for a cover is not.
      await _fetchingCovers?.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      if (!mounted) return;
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
                          covers: _covers,
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
    required this.covers,
    required this.boundaryKey,
    required this.busy,
    required this.onExport,
  });

  static const _height = 180.0;

  final ShareCardFormat format;
  final ShareCardData data;
  final Map<String, ImageProvider> covers;

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
                      child: YearShareCard(
                        format: format,
                        data: data,
                        covers: covers,
                      ),
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

/// One artist's square on the card: their cover, or their initial.
///
/// A raw [Image] rather than `ArtworkImage`, deliberately. The design
/// system's artwork fades in when its bytes arrive, and this card is
/// captured in a single frame - a fade caught halfway is a cover
/// exported at forty per cent opacity. Everything here is either fully
/// painted on the first frame or is the monogram.
class _Cover extends StatelessWidget {
  const _Cover({required this.edge, required this.name, this.image});

  final double edge;
  final String name;
  final ImageProvider? image;

  /// The one letter a coverless square shows. Digits count as letters
  /// here: a band called 65daysofstatic gets a 6 rather than a blank.
  static String _initial(String name) {
    for (final rune in name.trim().runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(char)) {
        return char.toUpperCase();
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final provider = image;
    return ClipRRect(
      borderRadius: WaxRadius.thumb,
      child: SizedBox(
        width: edge,
        height: edge,
        child: provider == null
            ? ColoredBox(
                color: colors.surface2,
                child: Center(
                  child: Text(
                    _initial(name),
                    style: WaxType.titleEntity.copyWith(
                      fontSize: edge * 0.5,
                      height: 1,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              )
            : Image(
                image: provider,
                fit: BoxFit.cover,
                // Nothing to fade from and nothing to fade to: the
                // bytes are decoded before this widget exists.
                gaplessPlayback: true,
              ),
      ),
    );
  }
}

/// The card itself, at its export size. Tokens, text, and whatever
/// covers were handed to it already decoded: nothing is fetched here, so
/// it renders the same offline and takes one frame.
class YearShareCard extends StatelessWidget {
  const YearShareCard({
    super.key,
    required this.format,
    required this.data,
    this.covers = const <String, ImageProvider>{},
  });

  final ShareCardFormat format;
  final ShareCardData data;

  /// Covers by artist name, decoded before this widget was built. A
  /// name with none draws a monogram, which is a designed state: a card
  /// exported on a plane is a card with monograms on it, not a card
  /// with holes.
  final Map<String, ImageProvider> covers;

  /// Everything on the card is sized against the 1080 the card is wide,
  /// so one set of proportions serves both shapes.
  static const _unit = 1080.0;

  double _s(double fraction) => _unit * fraction;

  /// The gap between the card's blocks.
  ///
  /// Tighter on the square, which is the shape with a real ceiling: it
  /// is as tall as it is wide and still owes a wordmark, a headline,
  /// three facts that wrap onto two runs when the numbers are long, and
  /// three names. The story has 840 pixels more to spend on two extra
  /// names, so it keeps the roomier rhythm.
  double get _blockGap => _s(format == ShareCardFormat.story ? 0.05 : 0.03);

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
                SizedBox(height: _blockGap),
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
                  SizedBox(height: _blockGap),
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
                          _Cover(
                            edge: _s(0.045),
                            name: artist.name,
                            image: covers[artist.name],
                          ),
                          SizedBox(width: _s(0.02)),
                          Expanded(
                            child: Text(
                              artist.name,
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
