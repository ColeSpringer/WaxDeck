import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

/// Every interactive component the catalogue shows, in the state where its
/// tap handlers exist, checked for a handler whose own node a parent drops.
///
/// On web a pointerdown that lands on a tappable semantics node is held
/// back, and the browser's click becomes that node's tap. A handler whose
/// node an ancestor excludes or merges is under that ancestor's node, so
/// its click runs the ancestor's action: a card's play button opened the
/// card. flutter_test has no such debouncer, so `tester.tap` cannot see it;
/// this walks the element tree instead.

/// The tap a widget handles itself, or null where it handles none.
Function? _tapOf(Widget widget) => switch (widget) {
  WaxTappable(:final onPressed, :final busy, :final inert) =>
    busy || inert ? null : onPressed,
  IconButton(:final onPressed) => onPressed,
  GestureDetector(:final onTap) => onTap,
  InkResponse(:final onTap) => onTap,
  _ => null,
};

/// A control is a node of its own by definition; the other handlers are
/// the gesture or the ink some node is drawn with.
bool _isControl(Widget widget) => widget is WaxTappable || widget is IconButton;

/// The framework's own handlers inside an ink response, an icon button or
/// a material toggle are that widget's plumbing, answering for it.
bool _isPlumbing(Widget widget) =>
    widget is InkResponse ||
    widget is IconButton ||
    widget is Switch ||
    widget is Checkbox ||
    widget is Radio;

/// Whether [widget] keeps its own tap out of the semantics tree.
bool _excludesItself(Widget widget) => switch (widget) {
  GestureDetector(:final excludeFromSemantics) => excludeFromSemantics,
  InkResponse(:final excludeFromSemantics) => excludeFromSemantics,
  _ => false,
};

/// Whether [element] is built inside an ink response, an icon button or a
/// material toggle, with no handler of its own owner's between.
bool _insidePlumbing(Element element) {
  var inside = false;
  element.visitAncestorElements((ancestor) {
    final above = ancestor.widget;
    if (_isPlumbing(above)) {
      inside = true;
      return false;
    }
    return _tapOf(above) == null;
  });
  return inside;
}

/// Whether an ancestor of [element] drops its semantics.
bool _excludedFromAbove(Element element) {
  var excluded = false;
  element.visitAncestorElements((ancestor) {
    final above = ancestor.widget;
    excluded =
        (above is Semantics && above.excludeSemantics) ||
        (above is ExcludeSemantics && above.excluding) ||
        above is MergeSemantics;
    return !excluded;
  });
  return excluded;
}

String _describe(Widget widget) => switch (widget) {
  WaxTappable(:final label) => 'WaxTappable("$label")',
  WaxIconButton(:final label) => 'WaxIconButton("$label")',
  Semantics(:final properties) when properties.label != null =>
    'Semantics("${properties.label}")',
  _ => widget.runtimeType.toString(),
};

/// How many handlers under [element] would merge into its node, counting
/// each outermost one once: a control's own plumbing is the control.
int _handlersUnder(Element element) {
  var count = 0;
  void visit(Element child) {
    if (_tapOf(child.widget) != null) {
      count++;
      return;
    }
    child.visitChildElements(visit);
  }

  element.visitChildElements(visit);
  return count;
}

/// Why the click on [element]'s handler would land on another node's
/// action, and that node's element; null where it reaches its own.
(String, Element)? _swallowedBy(Element element) {
  final widget = element.widget;
  final tap = _tapOf(widget);
  if (tap == null) return null;
  // No node of its own, from an ExcludeSemantics above or its own
  // excludeFromSemantics, so the click falls to whatever tappable node is
  // drawn around it. Plumbing excludes itself by design and answers for
  // its owner.
  if (!_isControl(widget) && _insidePlumbing(element)) return null;
  var dropped = _excludesItself(widget);
  (String, Element)? verdict;
  element.visitAncestorElements((ancestor) {
    final above = ancestor.widget;
    // Nothing reaches a handler a pointer cannot.
    if (above is IgnorePointer && above.ignoring) return false;
    if (above is AbsorbPointer && above.absorbing) return false;
    if (above is MergeSemantics) {
      if (_handlersUnder(ancestor) > 1) verdict = ('merged', ancestor);
      return false;
    }
    if (above is ExcludeSemantics && above.excluding) dropped = true;
    if (above is! Semantics) return true;
    final onTap = above.properties.onTap;
    if (!above.excludeSemantics) {
      if (onTap == null) return true;
      // A node an ancestor excludes in turn is no node at all.
      if (_excludedFromAbove(ancestor)) return true;
      // A handler with a node of its own sits on top of this one.
      if (!dropped) return false;
    }
    // An excluded node with no tap is no tappable element on web, so the
    // pointer reaches the framework and the handler; look further up.
    if (onTap == null) return true;
    // A node's own gesture or ink carries the very callback it does; a
    // control is a node of its own and never belongs to another's.
    if (_isControl(widget) || !identical(onTap, tap)) {
      verdict = (dropped ? 'dropped' : 'excluded', ancestor);
    }
    return false;
  });
  return verdict;
}

/// Every handler under [root] whose click a web build hands to a node
/// other than its own, each with the chain from that node down to it.
List<String> _hiddenHandlers(Element root) {
  final hits = <String>[];
  void visit(Element element) {
    if (_swallowedBy(element) case (final why, final node)) {
      final chain = <Widget>[element.widget];
      element.visitAncestorElements((ancestor) {
        chain.add(ancestor.widget);
        return ancestor != node;
      });
      // Private framework layers are noise in a chain read by a person.
      final path = chain.reversed
          .where((widget) => !widget.runtimeType.toString().startsWith('_'))
          .map(_describe)
          .join(' > ');
      hits.add('$why: $path');
    }
    element.visitChildElements(visit);
  }

  visit(root);
  return hits;
}

/// The mice [_hover] has put down and not yet lifted.
final _mice = <TestGesture>[];

/// Rests a mouse on the centre of the first match of [finder].
Future<void> _hover(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  _mice.add(gesture);
  addTearDown(_liftMice);
  await gesture.moveTo(tester.getCenter(finder.first));
  // A fixed wait, not a settle: a playing indicator never comes to rest.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

Future<void> _liftMice() async {
  for (final mouse in _mice) {
    await mouse.removePointer();
  }
  _mice.clear();
}

/// Fails unless some card's play disc is showing: a reveal that did not
/// happen would pass the walk for nothing.
void _expectPlayRevealed(WidgetTester tester) => expect(
  tester
      .widgetList<HoverPlayDisc>(find.byType(HoverPlayDisc))
      .any((disc) => disc.visible),
  isTrue,
  reason: 'a play disc is revealed',
);

/// One component and how to bring out the handlers it only builds on
/// demand.
typedef _Scenario = ({
  String name,
  Widget Function() build,
  Future<void> Function(WidgetTester tester)? reveal,
});

_Scenario _scenario(
  String name,
  Widget Function() build, {
  Future<void> Function(WidgetTester tester)? reveal,
}) => (name: name, build: build, reveal: reveal);

/// One callback a node and its ink share, as the components do.
void _noop() {}

const _tile = MediaTileData(title: 'Salt Harbour', subtitle: 'Nightjar');

const _music = NowPlayingData(
  title: 'Salt Harbour',
  subtitle: 'Nightjar',
  position: Duration(minutes: 2, seconds: 41),
  duration: Duration(minutes: 4, seconds: 5),
  playing: true,
  starred: true,
  volume: 0.6,
);

const _destinations = <WaxDestination>[
  WaxDestination(name: 'home', label: 'Home', glyph: WaxIcons.home),
  WaxDestination(name: 'music', label: 'Music', glyph: WaxIcons.music),
];

const _secondary = <WaxNavEntry>[
  WaxNavLink(
    WaxDestination(
      name: 'settings',
      label: 'Settings',
      glyph: WaxIcons.settings,
    ),
  ),
  WaxNavGroup(
    name: 'curation',
    label: 'Curation',
    glyph: WaxIcons.admin,
    children: <WaxDestination>[
      WaxDestination(name: 'users', label: 'Users', glyph: WaxIcons.admin),
    ],
  ),
];

/// [_music] with the end timecode's span switch named, as a book's bar is.
const _spanned = NowPlayingData(
  title: 'Salt Harbour',
  subtitle: 'Nightjar',
  position: Duration(minutes: 2, seconds: 41),
  duration: Duration(minutes: 4, seconds: 5),
  playing: true,
  starred: true,
  volume: 0.6,
  spanLabel: 'Show the whole book',
);

DeckBarActions _deckActions({VoidCallback? onSpanToggle}) => DeckBarActions(
  onPlayPause: () {},
  onNext: () {},
  onPrevious: () {},
  onShuffle: () {},
  onRepeat: () {},
  onSeek: (_) {},
  onStar: (_) {},
  onQueue: () {},
  onLyrics: () {},
  onCast: () {},
  onVolume: (_) {},
  onMute: () {},
  onMore: () {},
  onExpand: () {},
  onSpanToggle: onSpanToggle,
);

final _position = ValueNotifier<Duration>(const Duration(seconds: 30));

final List<_Scenario> _scenarios = <_Scenario>[
  _scenario(
    'buttons in every state',
    () => Wrap(
      children: <Widget>[
        WaxButton(label: 'Play', icon: WaxIcons.play, onPressed: () {}),
        WaxButton(label: 'Scan', busy: true, onPressed: () {}),
        const WaxButton(label: 'Downloading', progress: 0.42, onPressed: null),
        const WaxButton(label: 'Queued', status: true, onPressed: null),
        WaxButton(label: 'Retry', detail: 'No space left', onPressed: () {}),
        WaxIconButton(
          glyph: WaxIcons.sleepTimer,
          label: 'Sleep timer',
          badge: '12',
          onPressed: () {},
        ),
        WaxIconButton(
          glyph: WaxIcons.refresh,
          label: 'Sweep',
          busy: true,
          onPressed: () {},
        ),
        StarButton(starred: true, onChanged: (_) {}),
        WaxPill(label: 'Speed', text: '1.4x', onPressed: () {}),
        WaxFab(
          label: 'Play everything',
          glyph: WaxIcons.play,
          onPressed: () {},
        ),
      ],
    ),
  ),
  _scenario(
    'a tappable with a value, a hint and a tooltip, and an inert one',
    () => Row(
      children: <Widget>[
        WaxTappable(
          label: 'Download',
          value: '42 percent',
          hint: 'Waits for Wi-Fi',
          tooltip: 'Waits for Wi-Fi',
          onPressed: _noop,
          child: const InkWell(onTap: _noop, child: Text('Download')),
        ),
        WaxTappable(
          label: 'Downloaded',
          inert: true,
          onPressed: () {},
          child: const Text('Downloaded'),
        ),
      ],
    ),
  ),
  _scenario(
    'the action bar',
    () => WaxActionBar(
      actions: <WaxAction>[
        WaxAction(
          label: 'Play',
          semanticsId: 'play',
          glyph: WaxIcons.play,
          emphasis: WaxActionEmphasis.primary,
          onPressed: () {},
        ),
        WaxAction(
          label: 'Download',
          semanticsId: 'busy',
          glyph: WaxIcons.downloads,
          state: const WaxActionState.busy(),
          onPressed: () {},
        ),
        const WaxAction(
          label: 'Downloading',
          semanticsId: 'progress',
          glyph: WaxIcons.downloads,
          state: WaxActionState.progress(0.42),
        ),
        const WaxAction(
          label: 'Downloaded',
          semanticsId: 'done',
          glyph: WaxIcons.downloads,
          state: WaxActionState.done(),
        ),
        const WaxAction(
          label: 'Queued',
          semanticsId: 'status',
          glyph: WaxIcons.downloads,
          state: WaxActionState.status(),
          detail: 'Waits for Wi-Fi',
        ),
        WaxAction(
          label: 'Retry download',
          semanticsId: 'failed',
          glyph: WaxIcons.downloads,
          state: const WaxActionState.failed(),
          detail: 'Not enough space',
          onPressed: () {},
        ),
      ],
      trailing: <Widget>[StarButton(starred: false, onChanged: (_) {})],
      overflow: WaxMenuButton<int>(
        items: const <WaxMenuItem<int>>[
          WaxMenuItem<int>(value: 1, label: 'Share'),
        ],
        onSelected: (_) {},
      ),
    ),
  ),
  _scenario(
    'an open info tip',
    () => const Align(
      alignment: Alignment.topLeft,
      child: WaxInfoTip(message: 'Counts only the plays you listened through'),
    ),
    reveal: (tester) async {
      await tester.tap(find.byType(WaxInfoTip));
      await tester.pumpAndSettle();
      expect(
        find.text('Counts only the plays you listened through'),
        findsOne,
        reason: 'the popover is open',
      );
    },
  ),
  _scenario(
    'search, filters and the rail',
    () => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            children: <Widget>[
              SearchField(hint: 'Search', onChanged: (_) {}),
              WaxTextField(label: 'Name', onChanged: (_) {}),
              FilterChipRow(
                chips: const <WaxFilterChip>[
                  WaxFilterChip(name: 'all', label: 'All'),
                  WaxFilterChip(
                    name: 'music',
                    label: 'Music',
                    glyph: WaxIcons.music,
                  ),
                ],
                selected: 'all',
                onSelect: (_) {},
              ),
            ],
          ),
        ),
        SizedBox(
          height: 320,
          child: FastScrollRail(
            letters: fastScrollLetters,
            selected: 'A',
            onLetter: (_) {},
          ),
        ),
      ],
    ),
  ),
  _scenario(
    'seek bars, the slider, the segmented control and a progress bar',
    () => Column(
      children: <Widget>[
        WaxSeekBar(
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 4),
          onSeek: (_) {},
        ),
        WaxSeekBar(
          position: const Duration(minutes: 1),
          duration: const Duration(minutes: 4),
          peaks: List<double>.filled(48, 0.5),
          onSeek: (_) {},
        ),
        WaxSlider(
          value: 0.6,
          label: 'Volume',
          glyph: WaxIcons.volume,
          mutedGlyph: WaxIcons.volumeMuted,
          onMute: () {},
          onChanged: (_) {},
        ),
        WaxSegmented(
          label: 'Order',
          selected: 'az',
          onSelect: (_) {},
          segments: const <WaxSegment>[
            WaxSegment(name: 'az', label: 'A-Z'),
            WaxSegment(name: 'added', label: 'Added'),
          ],
        ),
        const WaxProgressBar(value: 0.42),
      ],
    ),
  ),
  _scenario(
    'lyrics and the visualizer',
    () => Column(
      children: <Widget>[
        SizedBox(
          height: 160,
          child: LyricsView(
            position: _position,
            onSeek: (_) {},
            lines: const <LyricLine>[
              LyricLine(at: Duration(seconds: 8), text: 'The tide comes in'),
              LyricLine(at: Duration(seconds: 40), text: 'and goes out'),
            ],
          ),
        ),
        SizedBox(
          height: 220,
          child: VisualizerStage(
            position: _position,
            duration: const Duration(minutes: 4),
            peaks: List<double>.filled(48, 0.5),
            mode: WaxVisualizerMode.waveform,
            onSeek: (_) {},
          ),
        ),
      ],
    ),
  ),
  _scenario(
    'car mode',
    () => SizedBox(
      height: 420,
      child: CarModeScaffold(
        now: _music,
        onPlayPause: () {},
        onNext: () {},
        onPrevious: () {},
        onExit: () {},
      ),
    ),
  ),
  _scenario(
    'a hovered card with its play, overflow and action',
    () => Align(
      alignment: Alignment.topLeft,
      child: MediaCard(
        width: 160,
        data: const MediaTileData(
          title: 'Salt Harbour',
          subtitle: 'Nightjar',
          badge: 'New',
          unplayed: true,
          downloaded: true,
          progress: 0.4,
          tooltip: 'Salt Harbour',
        ),
        playing: true,
        captions: WaxCaptionMode.onHover,
        onTap: () {},
        onPlay: () {},
        onMore: () {},
        action: MediaCardAction(
          glyph: WaxIcons.star,
          label: 'Pin',
          onPressed: () {},
        ),
      ),
    ),
    reveal: (tester) async {
      await _hover(tester, find.byType(ArtworkImage));
      _expectPlayRevealed(tester);
    },
  ),
  _scenario(
    'a hovered playable card without chips',
    () => Align(
      alignment: Alignment.topLeft,
      child: MediaCard(width: 160, data: _tile, onTap: () {}, onPlay: () {}),
    ),
    reveal: (tester) async {
      await _hover(tester, find.byType(ArtworkImage));
      _expectPlayRevealed(tester);
    },
  ),
  _scenario(
    'a page scaffold with its back and its actions',
    () => SizedBox(
      height: 600,
      child: WaxScaffold(
        title: 'Albums',
        onBack: () {},
        actions: <Widget>[
          WaxIconButton(
            glyph: WaxIcons.search,
            label: 'Search',
            onPressed: () {},
          ),
        ],
        body: const Text('content'),
      ),
    ),
  ),
  _scenario(
    'prose that takes a tap, alone and inside a control',
    () => Column(
      children: <Widget>[
        const WaxProse('A task account', onTap: _noop),
        WaxTappable(
          label: 'A task',
          onPressed: _noop,
          child: const InkWell(
            onTap: _noop,
            child: WaxProse('A task account', onTap: _noop),
          ),
        ),
      ],
    ),
  ),
  _scenario(
    'a hovered shelf',
    () => ShelfRow(
      title: 'Recently added',
      actionLabel: 'See all',
      onAction: () {},
      cardWidth: 120,
      items: <MediaTileData>[for (var i = 0; i < 8; i++) _tile],
      onTapItem: (_) {},
      onPlayItem: (_) {},
      onMoreItem: (_) {},
    ),
    reveal: (tester) async {
      await _hover(tester, find.byType(ArtworkImage));
      _expectPlayRevealed(tester);
    },
  ),
  _scenario(
    'rows',
    () => Column(
      children: <Widget>[
        MediaListRow(
          data: const MediaTileData(
            title: 'Harbour Lights',
            trailingText: '4:18',
            trailingDetail: '12',
            progress: 0.3,
          ),
          leadingIndex: 5,
          playing: true,
          onTap: () {},
          onMore: () {},
          actions: <Widget>[
            WaxIconButton(
              glyph: WaxIcons.downloads,
              label: 'Download',
              onPressed: () {},
            ),
          ],
        ),
        MediaListRow(
          data: _tile,
          onTap: () {},
          onSelect: (_) {},
          onLongPress: () {},
        ),
        WaxOptionRow(
          title: 'Kitchen',
          subtitle: 'Speaker',
          glyph: WaxIcons.cast,
          onTap: () {},
          trailing: WaxIconButton(
            glyph: WaxIcons.more,
            label: 'More',
            onPressed: () {},
          ),
        ),
        SectionHeader(
          title: 'Albums',
          info: 'Counts only albums with every track present',
          actionLabel: 'New',
          onAction: () {},
        ),
      ],
    ),
  ),
  _scenario(
    'an open disclosure with a control inside',
    () => WaxDisclosure(
      title: 'Edition',
      children: <Widget>[
        const MonoDetailRow(label: 'Publisher', value: 'Harbour Press'),
        WaxButton(label: 'Copy', onPressed: () {}),
      ],
    ),
    reveal: (tester) async {
      await tester.tap(find.text('Edition'));
      await tester.pumpAndSettle();
      expect(find.text('Harbour Press'), findsOne, reason: 'it is open');
    },
  ),
  _scenario(
    'an ink tappable row',
    () => WaxInkTappable(
      label: 'Kitchen, speaker',
      onPressed: _noop,
      borderRadius: WaxRadius.card,
      child: const Padding(
        padding: EdgeInsets.all(WaxSpace.s12),
        child: Text('Kitchen'),
      ),
    ),
  ),
  _scenario(
    'empty and error states',
    () => Row(
      children: <Widget>[
        Expanded(
          child: EmptyState(
            glyph: WaxIcons.podcasts,
            title: 'No podcasts yet',
            actionLabel: 'Find podcasts',
            onAction: () {},
          ),
        ),
        Expanded(
          child: ErrorState(
            message: "Can't reach the server.",
            detail: 'ERR_CONNECTION_REFUSED',
            onRetry: () {},
          ),
        ),
      ],
    ),
  ),
  _scenario(
    'a Load more footer, ready and a scroll\'s page',
    () => Column(
      children: <Widget>[
        LoadMoreFooter(
          label: 'Load more episodes',
          loading: false,
          onLoadMore: () {},
        ),
        LoadMoreFooter(
          label: 'Load more episodes',
          loading: true,
          onLoadMore: () {},
        ),
      ],
    ),
  ),
  _scenario(
    'stat tiles, a grid and figures',
    () => Column(
      children: <Widget>[
        WaxStatGrid(
          tiles: <StatTile>[
            StatTile(
              label: 'Health',
              value: '82',
              caption: '311 items want attention from somebody soon',
              glyph: WaxIcons.admin,
              onTap: () {},
            ),
            const StatTile(
              label: 'Pending',
              value: '12',
              caption: 'Items waiting for review by the catalogue team',
            ),
          ],
        ),
        const Row(
          children: <Widget>[
            StatFigure(value: '2h 6m', caption: 'listened'),
            StatFigure(value: '10', caption: 'sessions'),
          ],
        ),
      ],
    ),
  ),
  for (final width in <double>[1000, 560])
    _scenario(
      'the console table at $width',
      () => MediaQuery(
        data: MediaQueryData(size: Size(width, 900)),
        child: SizedBox(
          width: width,
          height: 400,
          child: WaxTable<String>(
            rows: const <String>['Scan library', 'Rebuild covers'],
            rowId: (job) => job,
            onRowTap: (_) {},
            columns: <WaxColumn<String>>[
              WaxColumn<String>(
                label: 'Job',
                text: (job) => job,
                cell: (context, job) => Text(job),
                priority: WaxColumnPriority.primary,
              ),
              WaxColumn<String>(
                label: 'State',
                text: (job) => 'running',
                cell: (context, job) => const CodecChip('running'),
                priority: WaxColumnPriority.detail,
              ),
            ],
            trailing: (context, job) => WaxIconButton(
              glyph: WaxIcons.close,
              label: 'Cancel $job',
              onPressed: () {},
            ),
          ),
        ),
      ),
    ),
  _scenario(
    'settings rows',
    () => Column(
      children: <Widget>[
        WaxSettingRow(
          title: 'Prepare the next track',
          help: 'Only on wifi',
          glyph: WaxIcons.downloads,
          control: WaxSwitch(
            value: true,
            label: 'Prepare the next track',
            onChanged: (_) {},
          ),
        ),
        WaxSettingRow(
          title: 'Crossfade',
          info: 'Overlaps the end of one track with the next',
          control: WaxSwitch(
            value: false,
            label: 'Crossfade',
            onChanged: (_) {},
          ),
        ),
        WaxSettingRow(
          title: 'Skip back by',
          control: WaxChoice<int>(
            value: 15,
            options: const <int>[10, 15, 30],
            labelFor: (value) => '$value seconds',
            label: 'Skip back by',
            onChanged: (_) {},
          ),
        ),
        WaxRadioGroup<String>(
          value: 'trash',
          onChanged: (_) {},
          options: const <WaxRadioOption<String>>[
            WaxRadioOption<String>(value: 'trash', label: 'Move to trash'),
            WaxRadioOption<String>(value: 'gone', label: 'Delete'),
          ],
        ),
      ],
    ),
  ),
  for (final sizeClass in WaxSizeClass.values)
    _scenario(
      'the shell frame, ${sizeClass.name}',
      () => SizedBox(
        width: switch (sizeClass) {
          WaxSizeClass.compact => 400,
          WaxSizeClass.medium => 640,
          WaxSizeClass.expanded => 760,
          WaxSizeClass.wide => 900,
        },
        height: 420,
        child: WaxShellFrame(
          sizeClass: sizeClass,
          destinations: _destinations,
          secondary: _secondary,
          selected: 'music',
          onSelect: (_) {},
          onToggleCollapsed: () {},
          account: const WaxAccount(
            name: 'sam',
            actions: <WaxAccountAction>[
              WaxAccountAction(
                name: 'signOut',
                label: 'Sign out',
                glyph: WaxIcons.close,
              ),
            ],
          ),
          onAccountAction: (_) {},
          sidebarHeader: const WaxWordmark(size: 18),
          content: const Center(child: Text('content')),
        ),
      ),
    ),
  _scenario(
    'banners, the resume offer and a side panel',
    () => Column(
      children: <Widget>[
        WaxBanner(
          tone: WaxBannerTone.notice,
          message: 'WaxDeck was updated.',
          actionLabel: 'Reload',
          onAction: () {},
        ),
        WaxBanner(
          tone: WaxBannerTone.caution,
          message: 'The library is read-only.',
          onDismiss: () {},
        ),
        DeckBarOffer(
          title: 'Salt Harbour',
          subtitle: 'Nightjar',
          onResume: () {},
          onDismiss: () {},
        ),
        SizedBox(
          height: 180,
          child: WaxSidePanel(
            title: 'Queue',
            onClose: () {},
            child: ListView(
              children: <Widget>[MediaListRow(data: _tile, onTap: () {})],
            ),
          ),
        ),
      ],
    ),
  ),
  _scenario(
    'the splitter',
    () => SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(width: 200),
          WaxSplitter(
            position: 200,
            min: 180,
            max: 400,
            onChanged: (_) {},
            onReset: () {},
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    ),
  ),
  _scenario(
    'the command palette and the shortcut sheet',
    () => Column(
      children: <Widget>[
        WaxCommandPalette(
          maxHeight: 280,
          onQueryChanged: (_) {},
          onRun: (_) {},
          onClose: () {},
          groups: const <WaxPaletteGroup>[
            WaxPaletteGroup(
              title: 'Actions',
              entries: <WaxPaletteEntry>[
                WaxPaletteEntry(
                  id: 'queue',
                  label: 'Show the queue',
                  detail: 'Views',
                  glyph: WaxIcons.queue,
                  shortcut: 'Q',
                ),
              ],
            ),
          ],
        ),
        WaxShortcutSheet(
          maxHeight: 240,
          onClose: () {},
          groups: const <WaxShortcutGroup>[
            WaxShortcutGroup(
              title: 'Playback',
              rows: <WaxShortcutRow>[
                WaxShortcutRow(label: 'Play or pause', keys: 'Space'),
              ],
            ),
          ],
        ),
      ],
    ),
  ),
  _scenario(
    'the entity header',
    () => EntityHeader(
      title: 'The Harbour Tapes',
      subtitle: 'Nightjar',
      metadata: '1975',
      description: 'Recorded over four winter nights.',
      actions: <WaxAction>[
        WaxAction(
          label: 'Play',
          semanticsId: 'play',
          glyph: WaxIcons.play,
          emphasis: WaxActionEmphasis.primary,
          onPressed: () {},
        ),
      ],
      trailing: <Widget>[StarButton(starred: true, onChanged: (_) {})],
    ),
  ),
  _scenario(
    'the station dial and the mini player',
    () => Column(
      children: <Widget>[
        SizedBox(
          width: 460,
          height: 260,
          child: StationDial(
            onTune: (_) {},
            onStop: () {},
            stations: const <DialStation>[
              DialStation(name: 'Coastal FM'),
              DialStation(name: 'Ora Lune', playing: true),
            ],
          ),
        ),
        SizedBox(
          width: 320,
          height: 96,
          child: MiniPlayer(
            now: _music,
            onRestore: () {},
            actions: _deckActions(),
          ),
        ),
      ],
    ),
  ),
  for (final sizeClass in <WaxSizeClass>[
    WaxSizeClass.compact,
    WaxSizeClass.wide,
  ])
    _scenario(
      'the deck bar, ${sizeClass.name}',
      () => SizedBox(
        width: sizeClass == WaxSizeClass.wide ? 1600 : 420,
        child: DeckBar(
          now: _spanned,
          sizeClass: sizeClass,
          actions: _deckActions(onSpanToggle: () {}),
        ),
      ),
    ),
  _scenario(
    'the player face',
    () => SizedBox(
      width: 400,
      height: 760,
      child: PlayerScaffold(
        now: _music,
        onCollapse: () {},
        onArtworkTap: () {},
        artworkLabel: 'Show the visualizer',
        artworkCaption: 'FLAC 24/96',
        trailingHeaderActions: <Widget>[
          WaxIconButton(glyph: WaxIcons.more, label: 'More', onPressed: () {}),
        ],
        seek: SeekCluster(now: _music, onSeek: (_) {}),
        transport: TransportCluster(
          playing: true,
          onPlayPause: () {},
          onPrevious: () {},
          onNext: () {},
          onShuffle: () {},
          onRepeat: () {},
        ),
        actionRow: WaxIconButton(
          glyph: WaxIcons.sleepTimer,
          label: 'Sleep timer',
          onPressed: () {},
        ),
      ),
    ),
  ),
];

/// Public components that draw and handle no tap of their own, so no
/// scenario has anything to check in them. A component missing from both
/// this list and every scenario fails the classification test below.
const _nonInteractive = <String>{
  'ArtworkCaption',
  'CarModeTheme',
  'ClampedBox',
  'CodecChip',
  'DomainBadge',
  'LiveLine',
  'LivePill',
  'MediaSplitBar',
  'MonoDetailRow',
  'PlayingIndicator',
  'ProgressRing',
  'ReadingColumn',
  'ReservedSize',
  'SkeletonShapes',
  'WaxBackdrop',
  'WaxBrandBlock',
  'WaxHairline',
  'WaxSpinner',
  'WaxWordmark',
};

/// The public widget classes `lib/src/components/` declares, render
/// object widgets included.
Set<String> _declaredComponents() => _publicWidgets(<String>[
  for (final file in Directory('lib/src/components').listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart')) file.readAsStringSync(),
]);

/// The public classes in [sources] that are widgets: a class extending a
/// framework `...Widget`, or one extending, however far up, a class of
/// [sources] that does, private or not.
///
/// A header is read whole, from `class` to its body's brace, so one the
/// formatter has broken across lines reads like one on a single line, and
/// the class's own type parameters are skipped bracket by bracket, so a
/// bound such as `Comparable<T>` is not taken for the superclass.
Set<String> _publicWidgets(List<String> sources) {
  final header = RegExp(
    r'^(?:(?:abstract|base|final|sealed|interface) )*class\s+(\w+)([^{;]*)\{',
    multiLine: true,
  );
  final superclasses = <String, String>{};
  for (final source in sources) {
    for (final match in header.allMatches(source)) {
      var rest = match.group(2)!.trimLeft();
      if (rest.startsWith('<')) {
        var depth = 0;
        var end = 0;
        for (; end < rest.length; end++) {
          if (rest[end] == '<') depth++;
          if (rest[end] == '>' && --depth == 0) break;
        }
        rest = rest.substring(end + 1);
      }
      final superclass = RegExp(r'^\s*extends\s+(\w+)').firstMatch(rest);
      if (superclass != null) superclasses[match[1]!] = superclass[1]!;
    }
  }
  bool isWidget(String name, Set<String> seen) => switch (superclasses[name]) {
    final up? => seen.add(name) && isWidget(up, seen),
    null => name.endsWith('Widget'),
  };
  return <String>{
    for (final name in superclasses.keys)
      if (!name.startsWith('_') && isWidget(name, <String>{})) name,
  };
}

/// Every widget type in the tree, generics dropped.
Set<String> _typesUnder(Element root) {
  final types = <String>{};
  void visit(Element element) {
    types.add(element.widget.runtimeType.toString().split('<').first);
    element.visitChildElements(visit);
  }

  visit(root);
  return types;
}

Future<void> _pumpScenario(WidgetTester tester, _Scenario scenario) async {
  tester.view.physicalSize = const Size(1800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildWaxTheme(),
      localizationsDelegates: waxLocalizationsDelegates,
      home: Scaffold(body: SingleChildScrollView(child: scenario.build())),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await scenario.reveal?.call(tester);
}

void main() {
  for (final scenario in _scenarios) {
    testWidgets('${scenario.name} keeps every tap on its own node', (
      tester,
    ) async {
      await _pumpScenario(tester, scenario);
      final hits = _hiddenHandlers(tester.binding.rootElement!);
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  }

  group('the walk itself', () {
    void other() {}

    Future<List<String>> walk(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      );
      return _hiddenHandlers(tester.binding.rootElement!);
    }

    const box = SizedBox.square(dimension: 40);

    testWidgets('passes a node over its own gesture', (tester) async {
      final hits = await walk(
        tester,
        Semantics(
          excludeSemantics: true,
          onTap: _noop,
          child: GestureDetector(onTap: _noop, child: box),
        ),
      );
      expect(hits, isEmpty);
    });

    testWidgets('flags a gesture under another excluded node', (tester) async {
      final hits = await walk(
        tester,
        Semantics(
          excludeSemantics: true,
          onTap: _noop,
          child: GestureDetector(onTap: other, child: box),
        ),
      );
      expect(hits.single, startsWith('excluded: '));
    });

    testWidgets('flags a control under an excluded node', (tester) async {
      final hits = await walk(
        tester,
        Semantics(
          excludeSemantics: true,
          onTap: _noop,
          child: WaxTappable(
            label: 'Play',
            onPressed: other,
            child: GestureDetector(onTap: other, child: box),
          ),
        ),
      );
      expect(hits.single, contains('WaxTappable("Play")'));
    });

    testWidgets('flags a dropped gesture under a tappable node', (
      tester,
    ) async {
      final hits = await walk(
        tester,
        Semantics(
          container: true,
          onTap: _noop,
          child: ExcludeSemantics(
            child: GestureDetector(onTap: other, child: box),
          ),
        ),
      );
      expect(hits.single, startsWith('dropped: '));
    });

    testWidgets('flags a self-excluded gesture under a tappable node', (
      tester,
    ) async {
      final hits = await walk(
        tester,
        Semantics(
          container: true,
          onTap: _noop,
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: other,
            child: box,
          ),
        ),
      );
      expect(hits.single, startsWith('dropped: '));
    });

    testWidgets('looks through ink to the node a child lands on', (
      tester,
    ) async {
      final hits = await walk(
        tester,
        Semantics(
          excludeSemantics: true,
          onTap: _noop,
          child: InkWell(
            onTap: _noop,
            child: GestureDetector(
              excludeFromSemantics: true,
              onTap: other,
              child: box,
            ),
          ),
        ),
      );
      expect(hits.single, startsWith('dropped: '));
    });

    testWidgets('flags two handlers merged into one node', (tester) async {
      final hits = await walk(
        tester,
        MergeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GestureDetector(onTap: _noop, child: box),
              GestureDetector(onTap: other, child: box),
            ],
          ),
        ),
      );
      expect(hits, hasLength(2));
      expect(hits.first, startsWith('merged: '));
    });

    testWidgets('passes what no pointer can reach', (tester) async {
      final hits = await walk(
        tester,
        Semantics(
          excludeSemantics: true,
          onTap: _noop,
          child: IgnorePointer(
            child: GestureDetector(onTap: other, child: box),
          ),
        ),
      );
      expect(hits, isEmpty);
    });
  });

  // The shapes a header can take that a one-line pattern misses, each a
  // component that would land unclassified with the test still green.
  group('the classification scan', () {
    test('finds a public component over a private base', () {
      expect(
        _publicWidgets(<String>[
          'class WaxOverPrivate extends _WaxBase {\n'
              '  const WaxOverPrivate();\n'
              '}\n'
              '\n'
              'abstract class _WaxBase extends StatelessWidget {\n'
              '  const _WaxBase();\n'
              '}\n',
        ]),
        <String>{'WaxOverPrivate'},
      );
    });

    test('finds one whose header the formatter wrapped', () {
      expect(
        _publicWidgets(<String>[
          'class WaxWrappedHeader<T extends Object>\n'
              '    extends StatelessWidget {\n'
              '}\n',
        ]),
        <String>{'WaxWrappedHeader'},
      );
    });

    test('finds one with a nested generic bound', () {
      expect(
        _publicWidgets(<String>[
          'class WaxBounded<T extends Comparable<T>> extends StatelessWidget '
              '{\n'
              '}\n',
        ]),
        <String>{'WaxBounded'},
      );
    });

    test('follows a base to another file, and leaves out what is no '
        'widget', () {
      expect(
        _publicWidgets(<String>[
          'class WaxOverThere extends WaxBase {}\n',
          'abstract class WaxBase extends StatefulWidget {}\n'
              'class WaxData {}\n'
              'class WaxState extends Equatable {}\n'
              'class _Private extends StatelessWidget {}\n',
        ]),
        <String>{'WaxOverThere', 'WaxBase'},
      );
    });
  });

  testWidgets('every component is audited or declared non-interactive', (
    tester,
  ) async {
    final audited = <String>{};
    for (final scenario in _scenarios) {
      await _pumpScenario(tester, scenario);
      audited.addAll(_typesUnder(tester.binding.rootElement!));
      // Each scenario starts from nothing, as it does in its own test.
      await _liftMice();
      await tester.pumpWidget(const SizedBox());
    }
    final declared = _declaredComponents();
    expect(declared, isNotEmpty, reason: 'the scan found the sources');
    final unclassified =
        declared.difference(audited).difference(_nonInteractive).toList()
          ..sort();
    expect(
      unclassified,
      isEmpty,
      reason:
          'give each a scenario above, or add it to _nonInteractive if it '
          'handles no tap',
    );
    final stale = _nonInteractive.difference(declared).toList()..sort();
    expect(stale, isEmpty, reason: 'no longer declared components');
  });
}
