import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart' show MediaType;
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../connect/device_picker.dart';
import '../player/lyrics.dart';
import '../player/now_playing_controller.dart';
import '../player/output_volume.dart';
import '../playlists/playlist_create.dart';
import '../queue/queue_controller.dart';
import '../queue/queue_view.dart';
import '../radio/radio_controller.dart';
import 'command_palette.dart';
import 'routes.dart';
import 'shortcut_sheet.dart';
import 'shortcuts.dart';

/// The keyboard's own nudge, whatever the medium: the spoken-word skip
/// intervals belong to the buttons shaped for them.
const Duration kKeyboardSeek = Duration(seconds: 10);

/// A volume step, as a fraction of full.
const double kVolumeStep = 0.05;

/// How the reference sheet groups its rows. The palette lists every
/// command under one heading instead.
enum WaxCommandSection {
  playback('Playback'),
  view('Views'),
  app('Everywhere');

  const WaxCommandSection(this.title);

  final String title;
}

/// One thing the app can be told to do, and the single source for the
/// three surfaces that would otherwise drift: the bindings, the palette,
/// and the sheet that teaches them.
class WaxCommand {
  const WaxCommand({
    required this.id,
    required this.label,
    required this.section,
    required this.run,
    this.glyph,
    this.activators = const <ShortcutActivator>[],
    this.enabled,
    this.whileTyping = false,
    this.inPalette = true,
  });

  /// Stable: it is the palette's row handle.
  final String id;

  /// A verb, sentence case.
  final String label;

  final WaxCommandSection section;

  /// Takes the context it is run from: a command outlives the surface
  /// that registered it.
  final void Function(BuildContext context, WidgetRef ref) run;

  final WaxGlyph? glyph;

  /// More than one where a chord is spelled per platform (control and
  /// meta both).
  final List<ShortcutActivator> activators;

  /// Whether it can do anything right now; null means always. Read by
  /// the palette and the sheet, never by the binding map - bindings
  /// built from live state would rebuild on every position tick.
  final bool Function(WidgetRef ref)? enabled;

  /// Whether the binding fires inside a text field. Only the palette's,
  /// which has to open from wherever the caret is.
  final bool whileTyping;

  /// Whether the palette offers it. False for the commands that operate
  /// the palette itself.
  final bool inPalette;

  bool isEnabled(WidgetRef ref) => enabled?.call(ref) ?? true;

  /// The keystroke to print, in this platform's spelling.
  String? get keys => activators.isEmpty ? null : describeActivator(activators);

  /// Same name, same place, same keys. What it *does* is excluded, so a
  /// rebuild that changes nothing offered publishes nothing - which is
  /// why a scoped `run` reads its state rather than closing over it.
  bool sameOffer(WaxCommand other) =>
      id == other.id &&
      label == other.label &&
      section == other.section &&
      glyph == other.glyph &&
      whileTyping == other.whileTyping &&
      inPalette == other.inPalette &&
      activators.length == other.activators.length &&
      Iterable<int>.generate(
        activators.length,
      ).every((i) => activators[i] == other.activators[i]);

  /// Whether two lists offer the same thing, in the same order.
  static bool sameOffers(List<WaxCommand> a, List<WaxCommand> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].sameOffer(b[i])) return false;
    }
    return true;
  }
}

/// The commands that are true on every screen. Screens add their own
/// through [CommandScope].
final List<WaxCommand> waxStandingCommands = <WaxCommand>[
  WaxCommand(
    id: 'play-pause',
    label: 'Play or pause',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.play,
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.space),
    ],
    enabled: _somethingToPlay,
    run: (context, ref) => togglePlayback(ref),
  ),
  WaxCommand(
    id: 'next',
    label: 'Next track',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.next,
    activators: _chord(LogicalKeyboardKey.arrowRight),
    enabled: _queuedPlayback,
    run: (context, ref) =>
        unawaited(ref.read(nowPlayingProvider.notifier).next()),
  ),
  WaxCommand(
    id: 'previous',
    label: 'Previous track',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.previous,
    activators: _chord(LogicalKeyboardKey.arrowLeft),
    enabled: _queuedPlayback,
    run: (context, ref) =>
        unawaited(ref.read(nowPlayingProvider.notifier).previous()),
  ),
  WaxCommand(
    id: 'seek-forward',
    label: 'Skip ahead 10 seconds',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.fastForward,
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.arrowRight, shift: true),
    ],
    enabled: _seekable,
    run: (context, ref) => seekBy(ref, kKeyboardSeek),
  ),
  WaxCommand(
    id: 'seek-back',
    label: 'Skip back 10 seconds',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.rewind,
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true),
    ],
    enabled: _seekable,
    run: (context, ref) => seekBy(ref, -kKeyboardSeek),
  ),
  WaxCommand(
    id: 'volume-up',
    label: 'Volume up',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.volume,
    activators: _chord(LogicalKeyboardKey.arrowUp),
    enabled: _hasLocalVolume,
    run: (context, ref) => nudgeVolume(ref, kVolumeStep),
  ),
  WaxCommand(
    id: 'volume-down',
    label: 'Volume down',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.volume,
    activators: _chord(LogicalKeyboardKey.arrowDown),
    enabled: _hasLocalVolume,
    run: (context, ref) => nudgeVolume(ref, -kVolumeStep),
  ),
  WaxCommand(
    id: 'mute',
    label: 'Mute or unmute',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.volumeMuted,
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.keyM),
    ],
    enabled: _hasLocalVolume,
    run: (context, ref) =>
        unawaited(ref.read(outputVolumeProvider.notifier).toggleMute()),
  ),
  WaxCommand(
    id: 'shuffle',
    label: 'Shuffle the queue',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.shuffle,
    enabled: (ref) => ref.read(queueControllerProvider).isNotEmpty,
    run: (context, ref) {
      final queue = ref.read(queueControllerProvider);
      ref.read(queueControllerProvider.notifier).setShuffle(!queue.shuffled);
    },
  ),
  WaxCommand(
    id: 'repeat',
    label: 'Change repeat',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.repeatAll,
    enabled: (ref) => ref.read(queueControllerProvider).isNotEmpty,
    run: (context, ref) {
      final queue = ref.read(queueControllerProvider);
      ref
          .read(queueControllerProvider.notifier)
          .setRepeat(nextQueueRepeat(queue.repeat));
    },
  ),
  WaxCommand(
    id: 'cast',
    label: 'Play on another device',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.cast,
    run: (context, ref) {
      final now = ref.read(nowPlayingProvider);
      unawaited(
        showDevicePicker(
          context,
          from: CastSource.here,
          currentPid: now.item?.pid,
          positionMs: now.session?.displayPosition.inMilliseconds ?? 0,
        ),
      );
    },
  ),

  WaxCommand(
    id: 'player',
    label: 'Open the player',
    section: WaxCommandSection.view,
    glyph: WaxIcons.expand,
    enabled: _somethingToPlay,
    run: (context, ref) => context.push(WaxRoute.nowPlaying),
  ),
  WaxCommand(
    id: 'queue',
    label: 'Show the queue',
    section: WaxCommandSection.view,
    glyph: WaxIcons.queue,
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.keyQ),
    ],
    run: (context, ref) => openQueue(context, ref),
  ),
  WaxCommand(
    id: 'lyrics',
    label: 'Show lyrics',
    section: WaxCommandSection.view,
    glyph: WaxIcons.lyrics,
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.keyL),
    ],
    // The deck bar's gate: words belong to a track that is playing.
    enabled: (ref) {
      final now = ref.read(nowPlayingProvider);
      final item = now.item;
      return now.session != null &&
          item != null &&
          item.mediaType == MediaType.music;
    },
    run: (context, ref) => openLyrics(context, ref),
  ),
  WaxCommand(
    id: 'visualizer',
    label: 'Open the visualizer',
    section: WaxCommandSection.view,
    glyph: WaxIcons.waveform,
    enabled: _somethingToPlay,
    run: (context, ref) => context.push(WaxRoute.visualizer),
  ),
  WaxCommand(
    id: 'car-mode',
    label: 'Open car mode',
    section: WaxCommandSection.view,
    glyph: WaxIcons.car,
    enabled: _somethingToPlay,
    run: (context, ref) => context.push(WaxRoute.carMode),
  ),

  WaxCommand(
    id: 'create-playlist',
    label: 'Create playlist',
    section: WaxCommandSection.app,
    glyph: WaxIcons.playlists,
    run: (context, ref) => unawaited(showCreatePlaylistDialog(context)),
  ),
  WaxCommand(
    id: 'palette',
    label: 'Open the command palette',
    section: WaxCommandSection.app,
    glyph: WaxIcons.search,
    activators: _chord(LogicalKeyboardKey.keyK),
    whileTyping: true,
    inPalette: false,
    run: (context, ref) => unawaited(showCommandPalette(context)),
  ),
  WaxCommand(
    id: 'search',
    label: 'Search',
    section: WaxCommandSection.app,
    glyph: WaxIcons.search,
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.slash),
    ],
    // The search screen autofocuses its own field.
    run: (context, ref) => context.go(WaxRoute.search),
  ),
  WaxCommand(
    id: 'shortcuts',
    label: 'Keyboard shortcuts',
    section: WaxCommandSection.app,
    glyph: WaxIcons.info,
    // Both spellings: web reports "?", the desktop embedders "/" with
    // shift. The question mark leads because it is what gets printed.
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.question, shift: true),
      SingleActivator(LogicalKeyboardKey.slash, shift: true),
    ],
    run: (context, ref) => unawaited(showShortcutSheet(context)),
  ),
];

/// One chord, both conventions, so a keyboard moved between machines
/// finds what it expects.
List<ShortcutActivator> _chord(LogicalKeyboardKey key) => <ShortcutActivator>[
  SingleActivator(key, control: true),
  SingleActivator(key, meta: true),
];

/// An item in the queue, or a station on the air.
bool _somethingToPlay(WidgetRef ref) =>
    ref.read(nowPlayingProvider).entry != null ||
    ref.read(radioPlaybackProvider).station != null;

/// Radio never queues, so there is nothing to step through.
bool _queuedPlayback(WidgetRef ref) =>
    ref.read(nowPlayingProvider).entry != null &&
    ref.read(radioPlaybackProvider).station == null;

bool _seekable(WidgetRef ref) => ref.read(nowPlayingProvider).session != null;

bool _hasLocalVolume(WidgetRef ref) => ref.read(localVolumeAvailableProvider);

/// Plays or pauses whatever this device is playing: a station stops and
/// starts, a live session toggles, and an entry left standing by a
/// failed start is taken back by starting it again. The deck bar's play
/// button runs this too.
void togglePlayback(WidgetRef ref) {
  if (ref.read(radioPlaybackProvider).station != null) {
    unawaited(ref.read(radioPlaybackProvider.notifier).toggle());
    return;
  }
  final session = ref.read(nowPlayingProvider).session;
  if (session != null) {
    unawaited(session.toggle());
    return;
  }
  ref.read(nowPlayingProvider.notifier).resume();
}

/// Nudges the playhead, never before the start.
void seekBy(WidgetRef ref, Duration delta) {
  final session = ref.read(nowPlayingProvider).session;
  if (session == null) return;
  final target = session.displayPosition + delta;
  unawaited(session.seek(target < Duration.zero ? Duration.zero : target));
}

/// Steps the output level from what the engine has: the fade and a
/// routed `set-volume` move it too.
void nudgeVolume(WidgetRef ref, double delta) {
  final level = (ref.read(outputVolumeProvider) + delta).clamp(0.0, 1.0);
  unawaited(ref.read(outputVolumeProvider.notifier).set(level));
}

/// Every command in force. Scoped ones are held per token, so a screen
/// leaving takes exactly its own away.
class CommandRegistry extends Notifier<List<WaxCommand>> {
  final Map<Object, List<WaxCommand>> _scoped = <Object, List<WaxCommand>>{};

  /// A scope withdraws post-frame, and a closing app runs those after
  /// the container is gone.
  bool _closed = false;

  @override
  List<WaxCommand> build() {
    ref.onDispose(() => _closed = true);
    return _all();
  }

  List<WaxCommand> _all() => <WaxCommand>[
    ...waxStandingCommands,
    for (final commands in _scoped.values) ...commands,
  ];

  /// Registering the same token again replaces what it carried.
  void register(Object token, List<WaxCommand> commands) {
    if (_closed) return;
    _scoped[token] = commands;
    state = _all();
  }

  void unregister(Object token) {
    if (_scoped.remove(token) == null || _closed) return;
    state = _all();
  }

  WaxCommand? byId(String id) {
    for (final command in state) {
      if (command.id == id) return command;
    }
    return null;
  }
}

final commandRegistryProvider =
    NotifierProvider<CommandRegistry, List<WaxCommand>>(CommandRegistry.new);

/// Puts a screen's commands in force while it is the screen on show.
///
/// On the tree is not the test: the shell keeps every visited branch
/// alive, so lifetime alone would accumulate every album screen anybody
/// had opened. The ticker mode and the route's `isCurrent` answer it, and
/// both are inherited. A sheet opened on the branch navigator counts as
/// covering, so a screen that needs its commands through its own sheet
/// opens that on the root navigator.
///
/// Registration is posted: writing a notifier from a dependency callback
/// runs inside a build.
class CommandScope extends ConsumerStatefulWidget {
  const CommandScope({required this.commands, required this.child, super.key});

  final List<WaxCommand> commands;
  final Widget child;

  @override
  ConsumerState<CommandScope> createState() => _CommandScopeState();
}

class _CommandScopeState extends ConsumerState<CommandScope> {
  final Object _token = Object();

  /// Held rather than looked up on the way out: by the time the posted
  /// withdrawal runs, this widget's ref is gone.
  late final CommandRegistry _registry = ref.read(
    commandRegistryProvider.notifier,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _publish();
  }

  @override
  void didUpdateWidget(CommandScope old) {
    super.didUpdateWidget(old);
    // By offer, not by list identity: a screen builds its commands
    // inline, so every rebuild hands over a new list.
    if (WaxCommand.sameOffers(old.commands, widget.commands)) return;
    _publish();
  }

  void _publish() {
    final showing =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final commands = widget.commands;
    final registry = _registry;
    final token = _token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (showing) {
        registry.register(token, commands);
      } else {
        registry.unregister(token);
      }
    });
  }

  @override
  void dispose() {
    final registry = _registry;
    final token = _token;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => registry.unregister(token),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The app's keyboard map, built from the registry.
///
/// [child] is held rather than built, so a scope registering or
/// withdrawing rebuilds this widget alone.
class CommandShortcuts extends ConsumerWidget {
  const CommandShortcuts({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(commandRegistryProvider);
    final bindings = <ShortcutActivator, VoidCallback>{};
    final typing = <ShortcutActivator, VoidCallback>{};
    for (final command in commands) {
      for (final activator in command.activators) {
        void run() {
          if (command.isEnabled(ref)) command.run(context, ref);
        }

        (command.whileTyping ? typing : bindings)[activator] = run;
      }
    }
    return AppShortcuts(
      bindings: bindings,
      typingBindings: typing,
      // This wraps every screen: grabbing focus would take it from a
      // field a screen autofocused.
      autofocus: false,
      child: child,
    );
  }
}

/// A keystroke as somebody would say it ("Ctrl K", "⌘ →"), in this
/// platform's spelling.
String? describeActivator(List<ShortcutActivator> activators) {
  final chosen = _forThisPlatform(activators);
  if (chosen is! SingleActivator) return null;
  final isApple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return <String>[
    if (chosen.control) 'Ctrl',
    if (chosen.meta) (isApple ? '⌘' : 'Meta'),
    if (chosen.alt) (isApple ? '⌥' : 'Alt'),
    if (chosen.shift) 'Shift',
    _keyLabel(chosen.trigger),
  ].join(' ');
}

ShortcutActivator _forThisPlatform(List<ShortcutActivator> activators) {
  final wantsMeta =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  for (final activator in activators) {
    if (activator is! SingleActivator) continue;
    if (activator.meta == wantsMeta && activator.control == !wantsMeta) {
      return activator;
    }
  }
  return activators.first;
}

/// The arrows are drawn rather than spelled.
String _keyLabel(LogicalKeyboardKey key) => switch (key) {
  LogicalKeyboardKey.arrowUp => '↑',
  LogicalKeyboardKey.arrowDown => '↓',
  LogicalKeyboardKey.arrowLeft => '←',
  LogicalKeyboardKey.arrowRight => '→',
  LogicalKeyboardKey.space => 'Space',
  LogicalKeyboardKey.enter => 'Enter',
  LogicalKeyboardKey.escape => 'Esc',
  LogicalKeyboardKey.slash => '/',
  LogicalKeyboardKey.question => '?',
  _ => key.keyLabel,
};
