import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'now_playing_controller.dart';
import 'playback_session.dart';

/// A surface that draws whatever is playing, with the live position.
///
/// The surfaces that need this - the lyrics panel beside the content,
/// the visualizer, car mode - are each mounted somewhere the player is
/// not, so none of them can be handed a session by the face. They read
/// the same state the deck bar does and follow it, which is also what
/// makes each one openable on its own: a location typed into the address
/// bar resolves to a screen that finds its own session.
///
/// The position arrives as a listenable rather than as a rebuild. Every
/// caller here is a full-screen picture over a piece of artwork, and
/// rebuilding one several times a second to move a playhead is the most
/// repeated frame work any of them could do.
class NowPlayingView extends ConsumerStatefulWidget {
  const NowPlayingView({required this.builder, required this.idle, super.key});

  /// Drawn with the session and the item it is for, plus the position.
  final Widget Function(
    BuildContext context,
    PlaybackSession session,
    ItemSummary item,
    ValueListenable<Duration> position,
  )
  builder;

  /// Drawn when nothing is playing, which every one of these surfaces
  /// can be opened into: a bookmark, a reload, a shortcut pressed in
  /// silence.
  final WidgetBuilder idle;

  @override
  ConsumerState<NowPlayingView> createState() => _NowPlayingViewState();
}

class _NowPlayingViewState extends ConsumerState<NowPlayingView> {
  final ValueNotifier<Duration> _position = ValueNotifier(Duration.zero);
  StreamSubscription<Duration>? _feed;
  PlaybackSession? _following;

  void _follow(PlaybackSession? session) {
    if (identical(session, _following)) return;
    _following = session;
    unawaited(_feed?.cancel());
    _feed = null;
    _position.value = session?.displayPosition ?? Duration.zero;
    _feed = session?.displayPositionStream.listen((at) {
      _position.value = at;
    });
  }

  @override
  void dispose() {
    unawaited(_feed?.cancel());
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowPlayingProvider);
    final session = now.session;
    final item = now.item;
    // In build rather than in a listener: the session is what this
    // watch already rebuilds for, and a `ref.listen` beside it would be
    // the same event arriving twice.
    _follow(session);
    if (session == null || item == null) return widget.idle(context);
    return widget.builder(context, session, item, _position);
  }
}
