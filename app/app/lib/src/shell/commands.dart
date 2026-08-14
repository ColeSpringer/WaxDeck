import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart' show MediaType;
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/dashboard_screen.dart';
import '../connect/device_picker.dart';
import '../desktop/mini_window.dart';
import '../l10n/l10n.dart';
import '../player/lyrics.dart';
import '../player/now_playing_controller.dart';
import '../player/output_volume.dart';
import '../playlists/playlist_create.dart';
import '../queue/queue_controller.dart';
import '../settings/settings_registry.dart';
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
  playback,
  view,
  app;

  String titleOf(AppLocalizations l10n) => switch (this) {
    WaxCommandSection.playback => l10n.shellCommandSectionPlayback,
    WaxCommandSection.view => l10n.shellCommandSectionView,
    WaxCommandSection.app => l10n.shellCommandSectionApp,
  };
}

/// One thing the app can be told to do, and the single source for the
/// three surfaces that would otherwise drift: the bindings, the palette,
/// and the sheet that teaches them.
class WaxCommand {
  const WaxCommand({
    required this.id,
    required this.section,
    this.label,
    required this.run,
    this.glyph,
    this.activators = const <ShortcutActivator>[],
    this.enabled,
    this.offered,
    this.whileTyping = false,
    this.inPalette = true,
  });

  /// Stable: it is the palette's row handle.
  final String id;

  /// A verb in the reader's language, or null for a standing command,
  /// whose name [commandLabel] looks up: a screen has a context in hand
  /// and words itself, the standing list is const above every one.
  final String? label;

  final WaxCommandSection section;

  /// Takes the context it is run from: a command outlives the surface
  /// that registered it.
  final void Function(BuildContext context, WidgetRef ref) run;

  final WaxGlyph? glyph;

  /// More than one where a chord is spelled per platform (control and
  /// meta both).
  final List<ShortcutActivator> activators;

  /// Whether it can do anything right now; null means always. Read by
  /// the palette, never by the binding map - bindings built from live
  /// state would rebuild on every position tick.
  final bool Function(WidgetRef ref)? enabled;

  /// Whether this build has the command at all; null means every build
  /// does. Read once by the registry, which withholds a command that
  /// answers false: it is not bound, not in the palette, and not taught
  /// by the sheet.
  ///
  /// Distinct from [enabled] because the two answer different questions,
  /// and the sheet is where the difference shows. "Nothing is playing
  /// yet" is not a reason to stop teaching the space bar, so the sheet
  /// prints a command whose [enabled] is false. "This browser tab has no
  /// window to shrink" is a reason never to print Ctrl+Shift+M, and no
  /// amount of playing anything will change it.
  final bool Function(Ref ref)? offered;

  /// Whether the binding fires inside a text field. Only the palette's,
  /// which has to open from wherever the caret is.
  final bool whileTyping;

  /// Whether the palette offers it. False for the commands that operate
  /// the palette itself.
  final bool inPalette;

  bool isEnabled(WidgetRef ref) => enabled?.call(ref) ?? true;

  /// The keystroke to print, in this platform's spelling.
  String? get keys => activators.isEmpty ? null : describeActivator(activators);

  /// Same name, place and keys. What it *does* is excluded, so a
  /// rebuild offering nothing new publishes nothing. A standing command
  /// has no label, so its id is what tells two of them apart.
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
    section: WaxCommandSection.playback,
    glyph: WaxIcons.next,
    activators: _chord(LogicalKeyboardKey.arrowRight),
    enabled: _queuedPlayback,
    run: (context, ref) =>
        unawaited(ref.read(nowPlayingProvider.notifier).next()),
  ),
  WaxCommand(
    id: 'previous',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.previous,
    activators: _chord(LogicalKeyboardKey.arrowLeft),
    enabled: _queuedPlayback,
    run: (context, ref) =>
        unawaited(ref.read(nowPlayingProvider.notifier).previous()),
  ),
  WaxCommand(
    id: 'seek-forward',
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
    section: WaxCommandSection.playback,
    glyph: WaxIcons.volume,
    activators: _chord(LogicalKeyboardKey.arrowUp),
    enabled: _hasLocalVolume,
    run: (context, ref) => nudgeVolume(ref, kVolumeStep),
  ),
  WaxCommand(
    id: 'volume-down',
    section: WaxCommandSection.playback,
    glyph: WaxIcons.volume,
    activators: _chord(LogicalKeyboardKey.arrowDown),
    enabled: _hasLocalVolume,
    run: (context, ref) => nudgeVolume(ref, -kVolumeStep),
  ),
  WaxCommand(
    id: 'mute',
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
    section: WaxCommandSection.view,
    glyph: WaxIcons.expand,
    enabled: _somethingToPlay,
    run: (context, ref) => context.push(WaxRoute.nowPlaying),
  ),
  WaxCommand(
    id: 'queue',
    section: WaxCommandSection.view,
    glyph: WaxIcons.queue,
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.keyQ),
    ],
    run: (context, ref) => openQueue(context, ref),
  ),
  WaxCommand(
    id: 'lyrics',
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
    section: WaxCommandSection.view,
    glyph: WaxIcons.waveform,
    enabled: _somethingToPlay,
    run: (context, ref) => context.push(WaxRoute.visualizer),
  ),
  WaxCommand(
    id: 'car-mode',
    section: WaxCommandSection.view,
    glyph: WaxIcons.car,
    enabled: _somethingToPlay,
    run: (context, ref) => context.push(WaxRoute.carMode),
  ),
  // Desktop only, and gated on what the compositor said rather than on
  // the platform: a Wayland session gets a plain small window, and a
  // window layer that would not answer at all gets no offer.
  miniWindowCommand,

  WaxCommand(
    id: 'create-playlist',
    section: WaxCommandSection.app,
    glyph: WaxIcons.playlists,
    run: (context, ref) => unawaited(showCreatePlaylistDialog(context)),
  ),
  WaxCommand(
    id: 'palette',
    section: WaxCommandSection.app,
    glyph: WaxIcons.search,
    activators: _chord(LogicalKeyboardKey.keyK),
    whileTyping: true,
    inPalette: false,
    run: (context, ref) => unawaited(showCommandPalette(context)),
  ),
  WaxCommand(
    id: 'search',
    section: WaxCommandSection.app,
    glyph: WaxIcons.search,
    activators: const <ShortcutActivator>[
      SingleActivator(LogicalKeyboardKey.slash),
    ],
    // The search screen autofocuses its own field.
    run: (context, ref) => context.go(WaxRoute.search),
  ),
  // Administrators only, and withheld rather than disabled for everyone
  // else: an account that cannot start a scan should not be taught a
  // command for it. `offered` is what does that - it is read once by the
  // registry, so the command is absent from the palette and from the
  // shortcut sheet alike.
  WaxCommand(
    id: 'scan-library',
    section: WaxCommandSection.app,
    glyph: WaxIcons.refresh,
    // Watched, not read: build() is the one place a predicate may, and a
    // read registers no dependency - a registry first built while the
    // session was still loading would hide the command for the
    // container's life. isAdminProvider rather than a fourth spelling
    // of roles.contains.
    offered: (ref) => ref.watch(isAdminProvider),
    run: (context, ref) => unawaited(startLibraryScan(ref)),
  ),
  WaxCommand(
    id: 'shortcuts',
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

/// What a command is called. A scoped one names itself; a standing one
/// is named here, because its list is const and above every context.
/// The id is a last resort `command_palette_test.dart` says is unused.
String commandLabel(AppLocalizations l10n, WaxCommand command) =>
    command.label ?? _standingLabel(l10n, command.id) ?? command.id;

String? _standingLabel(AppLocalizations l10n, String id) => switch (id) {
  'play-pause' => l10n.shellCommandPlayPause,
  'next' => l10n.shellCommandNext,
  'previous' => l10n.shellCommandPrevious,
  'seek-forward' => l10n.shellCommandSeekForward,
  'seek-back' => l10n.shellCommandSeekBack,
  'volume-up' => l10n.shellCommandVolumeUp,
  'volume-down' => l10n.shellCommandVolumeDown,
  'mute' => l10n.shellCommandMute,
  'shuffle' => l10n.shellCommandShuffle,
  'repeat' => l10n.shellCommandRepeat,
  'cast' => l10n.shellCommandCast,
  'player' => l10n.shellCommandPlayer,
  'queue' => l10n.shellCommandQueue,
  'lyrics' => l10n.shellCommandLyrics,
  'visualizer' => l10n.shellCommandVisualizer,
  'car-mode' => l10n.shellCommandCarMode,
  // Declared in the desktop half, offered only where there is a window
  // to shrink, and named here with the rest of the standing list.
  'mini-window' => l10n.shellCommandMiniWindow,
  'create-playlist' => l10n.shellCommandCreatePlaylist,
  'palette' => l10n.shellCommandPalette,
  'search' => l10n.shellCommandSearch,
  'scan-library' => l10n.shellCommandScanLibrary,
  'shortcuts' => l10n.shellCommandShortcuts,
  _ => null,
};

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

/// Plays or pauses whatever this device is playing. The deck bar's play
/// button and the mini player's run this too; the verb itself lives on
/// the controller that owns playback, because the tray menu needs it
/// from outside the widget tree.
void togglePlayback(WidgetRef ref) =>
    ref.read(nowPlayingProvider.notifier).togglePlayback();

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
  ///
  /// Cleared in [build], because Riverpod runs disposal callbacks before
  /// a recompute too: latched, the mini window's probe would freeze this
  /// registry seconds after launch.
  bool _closed = false;

  /// The standing commands this build has, settled in [build] because
  /// that is the only place a predicate may watch what it depends on -
  /// and the mini window's answer arrives after a platform probe, so a
  /// set decided once at startup would be decided too early.
  List<WaxCommand> _standing = const <WaxCommand>[];

  @override
  List<WaxCommand> build() {
    _closed = false;
    ref.onDispose(() => _closed = true);
    _standing = <WaxCommand>[
      for (final command in waxStandingCommands)
        if (command.offered?.call(ref) ?? true) command,
    ];
    return _all();
  }

  List<WaxCommand> _all() => <WaxCommand>[
    ..._standing,
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
