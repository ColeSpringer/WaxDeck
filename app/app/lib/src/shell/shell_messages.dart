import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';

/// The runs of messages the shell coalesces, one per feature that raises
/// them in bursts. Named here so a run cannot be mistyped into queueing,
/// and apart from the semantics identifiers an offer coalesces by.
enum ShellChannel {
  bookPosition,
  bookSettings,
  bookTools,
  bookmarks,
  defects,
  devices,
  downloads,
  episodes,
  instantMix,
  itemDelete,
  itemDetach,
  listing,
  markOlder,
  mixes,
  opml,
  pins,
  playlists,
  podcasts,
  queueRestore,
  radio,
  rating,
  remote,
  scrobbling,
  seriesMerge,
  shares,
  similarTracks,
  skippedUnplayable,
  spokenEffects,
  tasks,
  uploads,
}

/// One transient message, raised through [shellMessengerProvider] and
/// drawn by [ShellMessageHost] around every signed-in page.
/// `lifecycle_banners.dart` is the same shape for standing state.
class ShellMessage {
  ShellMessage({
    required String text,
    this.actionLabel,
    this.onAction,
    this.actionSemanticsId,
    this.channel,
    this.persist = false,
  }) : build = ((_) => text);

  /// A message whose words are chosen where they are drawn rather than
  /// where they are raised.
  ///
  /// Most callers have a `BuildContext` and read `context.l10n` at the
  /// leaf, which is the rule. A notifier has neither, and the two ways
  /// around that - holding a context or reading a locale from a
  /// provider - are both the thing the rule forbids. So the caller
  /// hands over what to say and the shell says it, in the locale the
  /// shell is being built in.
  ShellMessage.localized(
    this.build, {
    this.actionLabel,
    this.onAction,
    this.actionSemanticsId,
    this.channel,
  }) : persist = false;

  /// The words, as a function of the locale drawing them. A message
  /// whose text was fixed where it was raised is one of these too, over
  /// a locale it ignores.
  final String Function(AppLocalizations l10n) build;

  final String? actionLabel;
  final VoidCallback? onAction;
  final String? actionSemanticsId;

  /// The run this message belongs to: the shell replaces an earlier one
  /// of the run, on the bar or waiting, rather than queueing a second.
  /// Null, the ordinary case, supersedes nothing unless it is an offer.
  final ShellChannel? channel;

  /// What the shell coalesces by: the channel, else the action's
  /// identifier, since the same offer raised twice is the same message.
  Object? get run => channel ?? actionSemanticsId;

  /// Whether an offer's bar waits for its action rather than timing out,
  /// until the next message takes its place. For an undo worth the wait.
  final bool persist;

  /// The words to draw, in the locale the shell has.
  String resolve(AppLocalizations l10n) => build(l10n);
}

/// The shell's transient-message channel.
class ShellMessenger extends Notifier<ShellMessage?> {
  /// The messenger, for a caller holding a context rather than a ref.
  static ShellMessenger of(BuildContext context) => ProviderScope.containerOf(
    context,
    listen: false,
  ).read(shellMessengerProvider.notifier);

  @override
  ShellMessage? build() => null;

  void show(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
    String? actionSemanticsId,
    ShellChannel? channel,
    bool persist = false,
  }) {
    state = ShellMessage(
      text: text,
      actionLabel: actionLabel,
      onAction: onAction,
      actionSemanticsId: actionSemanticsId,
      channel: channel,
      persist: persist,
    );
  }

  /// Raises a message whose sentence is picked where it is drawn, for a
  /// caller with no `BuildContext` to read one from.
  void showLocalized(
    String Function(AppLocalizations l10n) build, {
    String? actionLabel,
    VoidCallback? onAction,
    String? actionSemanticsId,
    ShellChannel? channel,
  }) {
    state = ShellMessage.localized(
      build,
      actionLabel: actionLabel,
      onAction: onAction,
      actionSemanticsId: actionSemanticsId,
      channel: channel,
    );
  }

  /// Drops the delivered message, so its action closure is not held for
  /// the session on a notifier nothing disposes.
  void clear() => state = null;
}

final shellMessengerProvider = NotifierProvider<ShellMessenger, ShellMessage?>(
  ShellMessenger.new,
);

/// Draws [shellMessengerProvider]'s messages as bars, one at a time: a
/// run replaces its own entry, on the bar or waiting, and never another
/// page's unread bar.
class ShellMessageHost extends ConsumerStatefulWidget {
  const ShellMessageHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ShellMessageHost> createState() => _ShellMessageHostState();
}

class _ShellMessageHostState extends ConsumerState<ShellMessageHost> {
  /// Messages waiting for the bar, oldest first.
  final _waiting = <ShellMessage>[];

  /// The message on the bar, while one is.
  ShellMessage? _showing;

  /// Whether that bar waits for its action; the next message then takes
  /// its place once it has been up for the usual time.
  bool _showingPersists = false;

  /// Running while a waiting bar has not been up for the usual time.
  Timer? _held;
  bool _yieldPending = false;

  /// The app's messenger, kept for dispose, which can no longer ask the
  /// tree for it.
  ScaffoldMessengerState? _messenger;

  static const _barTime = Duration(seconds: 4);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _held?.cancel();
    // The bar would outlive the session on the sign-in screen, its action
    // live. After the frame, since the tree is locked while this runs.
    final messenger = _messenger;
    if (_showing != null && messenger != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (messenger.mounted) {
          messenger
            ..clearSnackBars()
            ..removeCurrentSnackBar();
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(shellMessengerProvider, (_, next) {
      if (next == null) return;
      // Delivered, so the action closure is not held for the session.
      ref.read(shellMessengerProvider.notifier).clear();
      final run = next.run;
      if (run != null) {
        final at = _waiting.indexWhere((m) => m.run == run);
        if (at >= 0) {
          _waiting[at] = next;
          return;
        }
        if (_showing?.run == run) {
          _waiting.insert(0, next);
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          return;
        }
      }
      _waiting.add(next);
      if (_showing == null) {
        _showNext();
      } else if (_showingPersists) {
        if (_held?.isActive ?? false) {
          _yieldPending = true;
        } else {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      }
    });
    return widget.child;
  }

  void _showNext() {
    _held?.cancel();
    _showing = null;
    _showingPersists = false;
    if (_waiting.isEmpty) return;
    final next = _waiting.removeAt(0);
    final action = next.onAction;
    final label = next.actionLabel;
    // An offer read aloud needs the time to reach its button.
    final persist =
        action != null &&
        label != null &&
        (next.persist || MediaQuery.accessibleNavigationOf(context));
    final messenger = ScaffoldMessenger.of(context);
    var answered = false;
    // Recorded only once it is up: with no Scaffold to draw it a debug
    // build asserts, and a bar that never showed must not hold the rest.
    final bar = messenger.showSnackBar(
      SnackBar(
        duration: _barTime,
        persist: persist,
        showCloseIcon: persist,
        // In the content, not the bar's action slot: SnackBarAction
        // takes no semantics identifier, and the e2e suite drives
        // the UI through those.
        content: Row(
          children: <Widget>[
            Expanded(child: Text(next.resolve(context.l10n))),
            if (action != null && label != null)
              WaxButton(
                label: label,
                kind: WaxButtonKind.text,
                semanticsId: next.actionSemanticsId,
                onPressed: () {
                  // Once: the bar is still up while it slides away.
                  if (answered) return;
                  answered = true;
                  action();
                  messenger.hideCurrentSnackBar();
                },
              ),
          ],
        ),
      ),
    );
    _showing = next;
    _showingPersists = persist;
    // Whatever already waits takes its place once it has had its time.
    _yieldPending = _waiting.isNotEmpty;
    if (persist) {
      _held = Timer(_barTime, () {
        if (mounted && _yieldPending) messenger.hideCurrentSnackBar();
      });
    }
    unawaited(
      bar.closed.then((_) {
        if (mounted) _showNext();
      }),
    );
  }
}
