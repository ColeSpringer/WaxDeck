import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'composites/album_composite.dart';
import 'composites/home_composite.dart';
import 'composites/player_composite.dart';
import 'pages/components_page.dart';
import 'pages/foundations_page.dart';
import 'sample_library.dart';

/// The design system's catalogue.
///
/// Two jobs: it is the surface a component is reviewed on before it is
/// used anywhere, and it is where the full-screen composites live, which
/// are what taste is judged against. Every page renders in all three
/// themes, at both densities, at two text scales, because a component
/// that only works in dark at 1.0 is not finished.
///
///     flutter run -d chrome   (from app/packages/waxdeck_ui/example)
void main() {
  runApp(const CatalogApp());
}

class CatalogApp extends StatefulWidget {
  const CatalogApp({super.key});

  @override
  State<CatalogApp> createState() => _CatalogAppState();
}

class _CatalogAppState extends State<CatalogApp> {
  WaxThemeVariant _variant = WaxThemeVariant.dark;
  WaxDensity _density = WaxDensity.comfortable;
  double _textScale = 1;
  int _page = 0;
  SampleArt? _art;

  @override
  void initState() {
    super.initState();
    SampleArt.generate(
      SampleArt.seeds,
    ).then((art) => setState(() => _art = art));
  }

  @override
  Widget build(BuildContext context) {
    final theme = buildWaxTheme(variant: _variant, density: _density);
    return MaterialApp(
      title: 'WaxDeck design system',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(_textScale)),
          child: _art == null
              ? const ColoredBox(color: Color(0xFF16130F))
              : _CatalogShell(
                  art: _art!,
                  variant: _variant,
                  density: _density,
                  textScale: _textScale,
                  page: _page,
                  onVariant: (v) => setState(() => _variant = v),
                  onDensity: (d) => setState(() => _density = d),
                  onTextScale: (s) => setState(() => _textScale = s),
                  onPage: (p) => setState(() => _page = p),
                ),
        ),
      ),
    );
  }
}

class _CatalogShell extends StatelessWidget {
  const _CatalogShell({
    required this.art,
    required this.variant,
    required this.density,
    required this.textScale,
    required this.page,
    required this.onVariant,
    required this.onDensity,
    required this.onTextScale,
    required this.onPage,
  });

  final SampleArt art;
  final WaxThemeVariant variant;
  final WaxDensity density;
  final double textScale;
  final int page;
  final ValueChanged<WaxThemeVariant> onVariant;
  final ValueChanged<WaxDensity> onDensity;
  final ValueChanged<double> onTextScale;
  final ValueChanged<int> onPage;

  static const List<String> _pages = <String>[
    'Foundations',
    'Components',
    'Home',
    'Album detail',
    'Player: music',
    'Player: podcast',
    'Player: audiobook',
    'Player: radio',
    'Deck bar',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: Row(
        children: <Widget>[
          _rail(context, colors),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context, WaxColors colors) => Container(
    width: 208,
    decoration: BoxDecoration(
      color: colors.surface1,
      border: Border(right: BorderSide(color: colors.hairline)),
    ),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.all(WaxSpace.s16),
            child: WaxWordmark(size: 22),
          ),
          Expanded(
            child: ListView(
              children: <Widget>[
                for (var i = 0; i < _pages.length; i++)
                  ListTile(
                    dense: true,
                    selected: i == page,
                    selectedColor: colors.accent,
                    title: Text(_pages[i], style: WaxType.label),
                    onTap: () => onPage(i),
                  ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(WaxSpace.s12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'THEME',
                  style: WaxType.overline.copyWith(color: colors.textTertiary),
                ),
                for (final v in WaxThemeVariant.values)
                  RadioListTile<WaxThemeVariant>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: v,
                    // ignore: deprecated_member_use
                    groupValue: variant,
                    // ignore: deprecated_member_use
                    onChanged: (value) => onVariant(value!),
                    title: Text(v.name, style: WaxType.bodySmall),
                  ),
                const SizedBox(height: WaxSpace.s8),
                Text(
                  'DENSITY',
                  style: WaxType.overline.copyWith(color: colors.textTertiary),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: density == WaxDensity.compact,
                  onChanged: (value) => onDensity(
                    value ? WaxDensity.compact : WaxDensity.comfortable,
                  ),
                  title: Text('Compact', style: WaxType.bodySmall),
                ),
                Text(
                  'TEXT SCALE ${textScale.toStringAsFixed(1)}',
                  style: WaxType.overline.copyWith(color: colors.textTertiary),
                ),
                Slider(
                  value: textScale,
                  min: 1,
                  max: 2,
                  divisions: 4,
                  onChanged: onTextScale,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _body(BuildContext context) => switch (page) {
    0 => const FoundationsPage(),
    1 => ComponentsPage(art: art),
    2 => HomeComposite(art: art, now: SampleLibrary.nowPlayingMusic(art)),
    3 => AlbumComposite(art: art, now: SampleLibrary.nowPlayingMusic(art)),
    4 => PlayerComposite(art: art),
    5 => PlayerComposite(art: art, face: WaxDomain.podcasts),
    6 => PlayerComposite(art: art, face: WaxDomain.audiobooks),
    7 => PlayerComposite(art: art, face: WaxDomain.radio),
    _ => _DeckBarGallery(art: art),
  };
}

class _DeckBarGallery extends StatelessWidget {
  const _DeckBarGallery({required this.art});

  final SampleArt art;

  @override
  Widget build(BuildContext context) {
    final bars = <String, NowPlayingData>{
      'Music': SampleLibrary.nowPlayingMusic(art),
      'Podcast': SampleLibrary.nowPlayingPodcast(art),
      'Audiobook': SampleLibrary.nowPlayingBook(art),
      'Radio': SampleLibrary.nowPlayingRadio(art),
    };
    return ListView(
      padding: const EdgeInsets.all(WaxSpace.s24),
      children: <Widget>[
        for (final entry in bars.entries) ...<Widget>[
          SectionHeader(overline: 'Deck bar', title: entry.key),
          for (final sizeClass in <WaxSizeClass>[
            WaxSizeClass.compact,
            WaxSizeClass.expanded,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: WaxSpace.s16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    sizeClass.name,
                    style: WaxType.caption.copyWith(
                      color: WaxColors.of(context).textTertiary,
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s4),
                  SizedBox(
                    width: sizeClass.isCompact ? 400 : 1000,
                    child: DeckBar(
                      now: entry.value,
                      sizeClass: sizeClass,
                      actions: DeckBarActions(
                        onPlayPause: () {},
                        onNext: () {},
                        onPrevious: () {},
                        onSkipBack: () {},
                        onSkipForward: () {},
                        onExpand: () {},
                        onSeek: (_) {},
                        onStar: (_) {},
                        onQueue: () {},
                        onLyrics: () {},
                        onCast: () {},
                        onMore: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: WaxSpace.s24),
        ],
        SectionHeader(overline: 'Deck bar', title: 'Blocked by the browser'),
        SizedBox(
          width: 400,
          child: DeckBar(
            now: SampleLibrary.nowPlayingMusic(art),
            sizeClass: WaxSizeClass.compact,
            autoplayBlocked: true,
            actions: DeckBarActions(onPlayPause: () {}, onExpand: () {}),
          ),
        ),
      ],
    );
  }
}
