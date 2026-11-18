import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../auth/auth_controller.dart';
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
  gapless,
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
  review,
  scrobbling,
  seriesMerge,
  shares,
  similarTracks,
  skippedUnplayable,
  spokenEffects,
  tasks,
  uploads,
}

/// One transient message, raised through a [ShellMessenger] and drawn by
/// [ShellMessageHost] around every page.
/// `lifecycle_banners.dart` is the same shape for standing state.
class ShellMessage {
  ShellMessage({
    required String text,
    this.actionLabel,
    this.onAction,
    this.actionSemanticsId,
    this.channel,
    this.persist = false,
    this.clearsBar = true,
    this.interrupts = false,
    this.subject,
  }) : build = ((_) => text),
       actionLabelOf = null;

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
    this.actionLabelOf,
    this.onAction,
    this.actionSemanticsId,
    this.channel,
  }) : actionLabel = null,
       persist = false,
       clearsBar = true,
       interrupts = false,
       subject = null;

  /// The words, as a function of the locale drawing them. A message
  /// whose text was fixed where it was raised is one of these too, over
  /// a locale it ignores.
  final String Function(AppLocalizations l10n) build;

  /// The action's label, worded where the message was raised.
  final String? actionLabel;

  /// The action's label chosen where it is drawn, for a caller with no
  /// locale to word it in (see [ShellMessage.localized]).
  final String Function(AppLocalizations l10n)? actionLabelOf;
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

  /// Whether the message is drawn clear of a [ShellMessageClearance] in
  /// sight. False for one raised for what shows next, as the bar it would
  /// clear leaves with the screen it is raised from. A page's floating
  /// button it rests above either way.
  final bool clearsBar;

  /// Whether the message takes the bar at once from the one on it, which
  /// comes back after it: for a confirmation whose undo is no use once it
  /// has waited out another message.
  final bool interrupts;

  /// What the message is about, with its [channel]: so it can be taken
  /// back once that is settled some other way (see [ShellMessenger.withdraw]).
  final Object? subject;

  /// The account whose session raised it, as its [ShellMessenger] was
  /// taken; null for a page outside a session.
  String? _account;

  /// The words to draw, in the locale the shell has.
  String resolve(AppLocalizations l10n) => build(l10n);

  /// The action's label in that locale, when there is an action.
  String? actionLabelIn(AppLocalizations l10n) =>
      actionLabelOf?.call(l10n) ?? actionLabel;
}

/// The messages raised to the shell: the last one, until a host has heard
/// it. Raised through a [ShellMessenger].
class ShellMessages extends Notifier<ShellMessage?> {
  @override
  ShellMessage? build() => null;

  void _raise(ShellMessage message) => state = message;

  /// Drops the delivered message, so its action closure is not held for
  /// the session on a notifier nothing disposes.
  void clear() => state = null;
}

final shellMessagesProvider = NotifierProvider<ShellMessages, ShellMessage?>(
  ShellMessages.new,
);

/// The shell's transient-message channel, for the session it is taken in.
///
/// A message belongs to the session it is raised in, which is the account
/// signed in as its messenger is taken, or none on a page outside a
/// session. A raiser takes it before an await to speak once its work
/// answers; if that session has ended by then, its answer is drawn
/// nowhere, neither on a sign-in screen nor in another account's session.
class ShellMessenger {
  ShellMessenger._(this._messages, this._withdrawn, this._account);

  /// The messenger, for a caller holding a context rather than a ref.
  static ShellMessenger of(BuildContext context) => ProviderScope.containerOf(
    context,
    listen: false,
  ).read(shellMessengerProvider);

  final ShellMessages _messages;
  final _Withdrawn _withdrawn;

  /// The account signed in as this was taken.
  final String? _account;

  void show(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
    String? actionSemanticsId,
    ShellChannel? channel,
    bool persist = false,
    bool clearsBar = true,
    bool interrupts = false,
    Object? subject,
  }) => _messages._raise(
    ShellMessage(
      text: text,
      actionLabel: actionLabel,
      onAction: onAction,
      actionSemanticsId: actionSemanticsId,
      channel: channel,
      persist: persist,
      clearsBar: clearsBar,
      interrupts: interrupts,
      subject: subject,
    ).._account = _account,
  );

  /// Takes back the message on [channel] about [subject], as its own
  /// action takes it: off the bar, or out of the queue. For an offer
  /// answered somewhere else than on its bar. Like a message, it belongs
  /// to the session this was taken in, and reaches no other.
  void withdraw(ShellChannel channel, Object subject) =>
      _withdrawn.send((channel: channel, subject: subject, account: _account));

  /// Raises a message whose sentence is picked where it is drawn, for a
  /// caller with no `BuildContext` to read one from.
  void showLocalized(
    String Function(AppLocalizations l10n) build, {
    String Function(AppLocalizations l10n)? actionLabelOf,
    VoidCallback? onAction,
    String? actionSemanticsId,
    ShellChannel? channel,
  }) => _messages._raise(
    ShellMessage.localized(
      build,
      actionLabelOf: actionLabelOf,
      onAction: onAction,
      actionSemanticsId: actionSemanticsId,
      channel: channel,
    ).._account = _account,
  );
}

/// A [ShellMessenger] for the account signed in now: one taken earlier
/// keeps the account it was taken for.
final shellMessengerProvider = Provider<ShellMessenger>(
  (ref) => ShellMessenger._(
    ref.watch(shellMessagesProvider.notifier),
    ref.watch(_withdrawnProvider.notifier),
    ref.watch(signedInAccountProvider),
  ),
);

/// A message taken back, by its channel and subject, by the session of
/// [account] (see [ShellMessage._account]).
typedef _Withdrawal = ({ShellChannel channel, Object subject, String? account});

/// The last message taken back, until a host has heard it.
class _Withdrawn extends Notifier<_Withdrawal?> {
  @override
  _Withdrawal? build() => null;

  void send(_Withdrawal? withdrawal) => state = withdrawal;
}

final _withdrawnProvider = NotifierProvider<_Withdrawn, _Withdrawal?>(
  _Withdrawn.new,
);

/// Draws the messages raised through [ShellMessenger] as bars, one at a
/// time, each by the host of the session it belongs to: a
/// run replaces its own entry, on the bar or waiting, and never another
/// page's unread bar. Each is drawn clear of any [ShellMessageClearance]
/// in sight, unless it says it clears no bar, and follows the bars it
/// clears while it is up.
///
/// The bar is a [WaxMessageBar] each page under the host draws over
/// itself, as each page's Scaffold drew Material's snack bar: every
/// [WaxScaffold] through [WaxPageMessages], a page on a bare Scaffold
/// through a [ShellMessageArea] of its own. So whatever opens over a page
/// covers its bar, and the bar comes in the page's focus and reading
/// order. The host keeps the queue, the timing and the lift. The bar
/// moves where it is rather than being drawn again, so it keeps its time
/// and is not announced twice.
///
/// One host is mounted around every page and one around a session's, which
/// draws the messages of the account signed in as it came and no other.
/// The outer leaves the messages to the inner while one is mounted, and
/// drops what it held as one comes, so the messages of the pages outside a
/// session and of the session itself never cross to the other's pages.
/// Meanwhile a page under the outer host and not under the inner, a dialog's
/// opened on the navigator around the session, draws the inner's bar.
class ShellMessageHost extends ConsumerStatefulWidget {
  const ShellMessageHost({required this.child, super.key}) : _public = false;

  /// The host around every page, for the pages outside a session: it draws
  /// what is raised with nobody signed in, whichever page, dialog or sheet
  /// raised it, and, while an account is signed in with no session's host
  /// mounted (a page with no session around it), that account's.
  const ShellMessageHost.public({required this.child, super.key})
    : _public = true;

  final Widget child;

  final bool _public;

  @override
  ConsumerState<ShellMessageHost> createState() => _ShellMessageHostState();
}

/// A message on the bar, worded, and what its action does there.
class _Bar {
  _Bar(
    this.message, {
    required this.text,
    required this.persist,
    this.label,
    this.onAction,
  });

  final ShellMessage message;
  final String text;
  final bool persist;
  final String? label;
  final VoidCallback? onAction;

  /// Whether its action has run or been taken off: the bar is still up
  /// while it leaves, and takes no press then.
  var answered = false;
}

/// What of the window decides where a message rests.
typedef _Insets = ({
  EdgeInsets padding,
  EdgeInsets viewPadding,
  double keyboard,
});

_Insets _insetsOf(BuildContext context) => (
  padding: MediaQuery.paddingOf(context),
  viewPadding: MediaQuery.viewPaddingOf(context),
  keyboard: MediaQuery.viewInsetsOf(context).bottom,
);

/// How far above a page's foot a message rests: the keyboard, else the
/// bottom of the view's padding.
double _keptAbove(_Insets insets) =>
    insets.keyboard > 0 ? insets.keyboard : insets.viewPadding.bottom;

/// [bar] where a floating snack bar rests in a Scaffold under [insets]:
/// along its foot, inside the padding at its sides and clear of [right],
/// [lift] higher.
Widget _resting(Widget bar, _Insets insets, double lift, {double right = 0}) =>
    Positioned(
      left: insets.padding.left,
      right: math.max(insets.padding.right, right),
      bottom: _keptAbove(insets) + lift,
      child: bar,
    );

/// Around a page that lays something along its right edge over itself,
/// as an index lays its letter rail: the page's messages rest clear of
/// it rather than under it, where it would be drawn over them and take
/// a screen reader's touch.
class ShellMessageMargin extends InheritedWidget {
  const ShellMessageMargin({
    required this.right,
    required super.child,
    super.key,
  });

  /// How far in from the page's right edge its messages keep.
  final double right;

  @override
  bool updateShouldNotify(ShellMessageMargin oldWidget) =>
      right != oldWidget.right;
}

/// [page] as a page the shell's messages are drawn on.
Widget _presentPage(Widget page) => ShellMessageArea(child: page);

/// [button], a page's floating button, as one every message rests above.
Widget _clearButton(Widget button) => ShellMessageClearance._floating(button);

/// A bar as pages draw it: what it draws, which their copies fly between
/// pages as, the bar itself, and how far they lift it.
typedef _Drawn = ({_Bar? message, Widget? bar, double lift});

/// The bar the pages draw, and, while a session's host is mounted under
/// this one, the session's, for a dialog opened over the session.
class _Shown extends InheritedWidget {
  const _Shown({required this.own, this.session, required super.child});

  final _Drawn own;
  final _Drawn? session;

  @override
  bool updateShouldNotify(_Shown oldWidget) =>
      own != oldWidget.own || session != oldWidget.session;
}

class _ShellMessageHostState extends ConsumerState<ShellMessageHost>
    with SingleTickerProviderStateMixin {
  /// Messages waiting for the bar, oldest first.
  final _waiting = <ShellMessage>[];

  /// The message on the bar, while one is.
  ShellMessage? _showing;

  /// Whether that bar waits for its action; the next message then takes
  /// its place once it has been up for the usual time.
  bool _showingPersists = false;

  /// Running while a waiting bar has not been up for the usual time.
  _Countdown? _held;
  bool _yieldPending = false;

  /// Running from when a bar that times out is up until its time is out,
  /// which takes it off.
  _Countdown? _airing;

  /// Whether every page in sight that draws the bar is covered by what
  /// opened over it, a sheet, a menu or a dialog: its time stands still
  /// meanwhile, as nobody can read it or take its action.
  var _covered = false;

  /// Running while [_covered]; how long each message has waited covered,
  /// and how far into the cover one raised under it arrived.
  Stopwatch? _cover;
  final _coveredFor = Expando<Duration>();
  final _coveredOnArrival = Expando<Duration>();

  /// Whether the bar on screen is on its way off, answered or yielding.
  bool _leaving = false;

  /// Whether the bar on screen was taken off it here, the next one still
  /// to be drawn.
  bool _cut = false;

  /// The bar drawn, from its entrance to the end of its exit.
  _Bar? _bar;

  /// [_bar] as the pages draw it.
  Widget? _drawn;

  /// Its entrance and exit.
  late final AnimationController _motion;

  /// Completes as the bar drawn goes.
  Completer<void>? _gone;

  /// The pages messages are drawn on and the bars they are drawn clear of,
  /// each while it is in the tree.
  final _declared = <_DeclaredState>{};

  /// The bar's flights between pages while each is in the air, oldest
  /// first, and the pages a flight has just set out for whose shuttle is
  /// still to be built.
  final _airborne = <_ShuttleState>[];
  final _announced = <_ShellMessageAreaState>{};

  /// How far the bar on screen is lifted, clear of what it clears.
  double _lift = 0;

  /// A lift measured once and waiting for the next frame to agree, so a
  /// bar on its way out and its successor on the way in move nothing.
  double? _settling;

  /// Whether a measure waits on the frame being drawn.
  var _watching = false;

  static const _barTime = Duration(seconds: 4);

  /// Material's own, for a floating bar's entrance and exit.
  static const _motionTime = Duration(milliseconds: 250);

  /// The host this one is mounted under, if any.
  _ShellMessageHostState? _outer;

  /// The hosts mounted under this one, which draw the messages meanwhile.
  final _inner = <_ShellMessageHostState>{};

  /// For a session's host, the account whose session it is.
  String? _account;

  /// The host drawing the messages now: the innermost one mounted under
  /// this one, else this.
  _ShellMessageHostState get _drawer =>
      _inner.isEmpty ? this : _inner.first._drawer;

  /// The pages and bars that count for the messages this host draws: its
  /// own, and the dialogs' opened over its session on the navigators
  /// around it.
  Iterable<_DeclaredState> get _counted sync* {
    yield* _declared;
    for (var outer = _outer; outer != null; outer = outer._outer) {
      if (outer._drawer != this) break;
      yield* outer._declared.where(
        (page) => page is _ShellMessageAreaState && page._overSession,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(duration: _motionTime, vsync: this)
      ..addStatusListener(_moved);
    if (!widget._public) _account = ref.read(signedInAccountProvider);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final outer = context.findAncestorStateOfType<_ShellMessageHostState>();
    if (outer != _outer) {
      _outer?._innerLeft(this);
      _outer = outer?.._innerCame(this);
    }
  }

  @override
  void deactivate() {
    _outer?._innerLeft(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _outer?._innerCame(this);
  }

  @override
  void dispose() {
    _held?.cancel();
    _airing?.cancel();
    _motion.dispose();
    super.dispose();
  }

  /// A host mounted under this one, a session's: what this one held was
  /// raised on the pages the session leaves behind, and goes with them,
  /// once the frame that brought the session in is drawn.
  void _innerCame(_ShellMessageHostState inner) {
    if (!_inner.add(inner)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _inner.isEmpty) return;
      _waiting.clear();
      _remove();
      setState(() {});
    });
  }

  /// A host under this one went, in a build: this one draws its own again
  /// once the frame is.
  void _innerLeft(_ShellMessageHostState inner) {
    if (!_inner.remove(inner)) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (mounted) setState(() {});
      })
      ..scheduleFrame();
  }

  /// What the bar draws changed: the hosts around this one that leave their
  /// messages to it draw it on their pages too.
  void _shownChanged() {
    for (var outer = _outer; outer != null; outer = outer._outer) {
      if (outer.mounted && outer._drawer == this) outer.setState(() {});
    }
  }

  /// Whether what the session of [account] raised or took back is this
  /// host's: a session's host hears its own account's; the public host
  /// what came with nobody signed in, and the account's signed in now
  /// while no session's host is mounted.
  bool _owns(String? account) => widget._public
      ? account == null || account == ref.read(signedInAccountProvider)
      : account == _account;

  @override
  Widget build(BuildContext context) {
    ref.listen(shellMessagesProvider, (_, next) {
      // A session's host under this one draws it.
      if (next == null || _inner.isNotEmpty) return;
      // Delivered, so the action closure is not held for the session.
      ref.read(shellMessagesProvider.notifier).clear();
      // Another session's word, its answer come after that session ended.
      if (!_owns(next._account)) return;
      _heard(next);
    });
    ref.listen(_withdrawnProvider, (_, taken) {
      if (taken == null || _inner.isNotEmpty) return;
      ref.read(_withdrawnProvider.notifier).send(null);
      if (!_owns(taken.account)) return;
      bool about(ShellMessage? message) =>
          message?.channel == taken.channel &&
          message?.subject == taken.subject;
      _waiting.removeWhere(about);
      if (_bar case final bar? when about(bar.message)) bar.answered = true;
      // Off the way an answered one goes.
      if (about(_showing) && !_cut && !_leaving) {
        _leaving = true;
        _hide();
      }
    });
    final drawer = _drawer;
    return WaxPageMessages(
      present: _presentPage,
      clear: _clearButton,
      child: _Shown(
        own: (message: _bar, bar: _drawn, lift: _lift),
        session: drawer == this
            ? null
            : (message: drawer._bar, bar: drawer._drawn, lift: drawer._lift),
        child: widget.child,
      ),
    );
  }

  /// Takes [next] into the queue, or onto the bar.
  void _heard(ShellMessage next) {
    if (_cover case final cover?) _coveredOnArrival[next] = cover.elapsed;
    final run = next.run;
    if (run != null) {
      final at = _waiting.indexWhere((m) => m.run == run);
      if (at >= 0) {
        _waiting[at] = next;
        return;
      }
      if (!_cut && _showing?.run == run) {
        _waiting.insert(0, next);
        _cutShowing();
        return;
      }
    }
    if (next.interrupts) {
      _waiting.insert(0, next);
      final showing = _showing;
      if (showing == null) {
        _showNext();
        return;
      }
      // Back after it for its whole time rather than what it had left:
      // it is drawn afresh, and a remainder can be too short to read.
      if (!_cut && !_hadItsTime) _waiting.insert(1, showing);
      _cutShowing();
      return;
    }
    _waiting.add(next);
    if (_showing == null) {
      _showNext();
    } else if (_showingPersists && !_cut) {
      if (_held?.isActive ?? false) {
        _yieldPending = true;
      } else {
        _leaving = true;
        _hide();
      }
    }
  }

  /// Whether something to clear is declared, for a message that clears
  /// [bars] or not.
  bool _clears({required bool bars}) => _counted.any(
    (declared) =>
        declared is _ShellMessageClearanceState && declared._asks(bars: bars),
  );

  /// How far to lift the bar to clear what is declared now, for a message
  /// that clears [bars] or not: above the highest in sight; where it is
  /// while a bar is still to be drawn, a screen between one and the next;
  /// else not at all.
  double _clearance({required bool bars}) {
    var most = 0.0;
    var measured = false;
    var coming = false;
    for (final bar in _counted.whereType<_ShellMessageClearanceState>()) {
      if (!bar._declares || !bar._asks(bars: bars)) continue;
      final rise = bar._rise();
      if (rise == null) {
        coming = true;
      } else {
        measured = true;
        most = math.max(most, rise);
      }
    }
    if (measured) return most;
    return coming ? _lift : 0;
  }

  void _place(double lift) {
    _settling = null;
    if (lift == _lift) return;
    setState(() => _lift = lift);
    _shownChanged();
  }

  /// A page or a bar was declared, withdrawn, or came into or out of
  /// sight.
  void _declarationsChanged() {
    final drawer = _drawer;
    if (drawer != this) return drawer._declarationsChanged();
    if (_showing != null) _watch();
  }

  /// The one flight that draws the bar while any is in the air: of those
  /// whose page is still there, the outermost navigator's, drawn above the
  /// pages of those inside it, and the oldest of equals. Two navigators can
  /// fly at once (a door from over the player pops it and moves inside the
  /// shell), and a move can cut another short or take its page away.
  _ShuttleState? get _carrier {
    _ShuttleState? carrier;
    for (final shuttle in _airborne) {
      if (!shuttle._canCarry || !shuttle._inSight) continue;
      if (carrier == null || shuttle._depth < carrier._depth) {
        carrier = shuttle;
      }
    }
    return carrier;
  }

  /// Whether the pages' copies stand aside for a flight: one carries the
  /// bar, or one is about to. A page a flight landed on waits for the
  /// rest, so no page shows its copy beside the bar in flight.
  bool get _flying => _announced.isNotEmpty || _carrier != null;

  /// A flight is setting out for [page]: told before the frame that first
  /// draws it, so every copy stands aside in that frame.
  void _flightTo(_ShellMessageAreaState page) {
    if (_airborne.any((shuttle) => shuttle._bound == page)) return;
    if (!_announced.add(page)) return;
    _flightsChanged();
    // One already in the air was turned towards it instead.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_announced.remove(page)) _flightsChanged();
    });
  }

  void _took(_ShuttleState shuttle) {
    _airborne.add(shuttle);
    _announced.remove(shuttle._bound);
  }

  void _landed(_ShuttleState shuttle) {
    if (_airborne.remove(shuttle)) _flightsChanged();
  }

  /// Has every flight and copy look again at which draws the bar: at once,
  /// or after a build that changed it, which may not mark another widget.
  void _flightsChanged() {
    if (!mounted) return;
    final binding = WidgetsBinding.instance;
    if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      binding
        ..addPostFrameCallback((_) => _flightsChanged())
        ..scheduleFrame();
      return;
    }
    for (final shuttle in _airborne) {
      shuttle._refresh();
    }
    for (final area in _counted.whereType<_ShellMessageAreaState>()) {
      area._copy?._refresh();
    }
  }

  /// Measures again once the frame being drawn is laid out, and after each
  /// frame while there is a bar to follow: one can move or change height
  /// without saying so.
  void _watch() {
    if (_watching) return;
    _watching = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
  }

  void _follow() {
    _watching = false;
    _checkCover();
    final showing = _showing;
    if (!mounted || showing == null || _cut) {
      _settling = null;
      return;
    }
    final bars = showing.clearsBar;
    final want = _clearance(bars: bars);
    if (want == _lift) {
      _settling = null;
    } else if (want == _settling) {
      _place(want);
    } else {
      _settling = want;
      // The frame that confirms it, which nothing else may ask for.
      WidgetsBinding.instance.scheduleFrame();
    }
    if (_clears(bars: bars) || _lift > 0 || _settling != null) _watch();
  }

  /// Pauses the bar's time while every page in sight that draws it is
  /// covered, and resumes it, with what it had left, once one is not.
  void _checkCover() {
    if (!mounted) return;
    final drawing = _counted.whereType<_ShellMessageAreaState>().where(
      (area) => area._draws && area._inSight,
    );
    final covered =
        _showing != null &&
        drawing.isNotEmpty &&
        !drawing.any((area) => area._inFront);
    if (covered == _covered) return;
    _covered = covered;
    for (final countdown in [_held, _airing]) {
      covered ? countdown?.pause() : countdown?.resume();
    }
    if (covered) {
      _cover = messageStopwatch()..start();
    } else {
      _uncovered();
    }
  }

  /// A message with no action that waited covered for longer than its own
  /// time goes unread rather than late; one with an action waits on.
  void _uncovered() {
    final span = _cover?.elapsed ?? Duration.zero;
    _cover = null;
    bool stale(ShellMessage message) {
      final covered =
          (_coveredFor[message] ?? Duration.zero) +
          span -
          (_coveredOnArrival[message] ?? Duration.zero);
      _coveredFor[message] = covered;
      _coveredOnArrival[message] = null;
      final acts =
          message.onAction != null &&
          message.actionLabelIn(context.l10n) != null;
      return covered > _barTime && !acts;
    }

    _waiting.removeWhere(stale);
    final showing = _showing;
    if (showing != null && !_cut && !_leaving && stale(showing)) {
      _cutShowing();
    }
  }

  /// Whether the bar on screen has had its time, or is on its way off.
  bool get _hadItsTime =>
      _leaving ||
      (_showingPersists
          ? !(_held?.isActive ?? false)
          : !(_airing?.isActive ?? true));

  /// Takes the bar on screen off at once; its going draws the next.
  void _cutShowing() {
    _cut = true;
    _remove();
  }

  void _showNext() {
    _held?.cancel();
    _airing?.cancel();
    _airing = null;
    _showing = null;
    _showingPersists = false;
    _leaving = false;
    _cut = false;
    if (_waiting.isEmpty) {
      _place(0);
      return;
    }
    final next = _waiting.removeAt(0);
    final action = next.onAction;
    final label = next.actionLabelIn(context.l10n);
    // An offer read aloud needs the time to reach its button.
    final persist =
        action != null &&
        label != null &&
        (next.persist || MediaQuery.accessibleNavigationOf(context));
    // Above the screen's bottom bar as measured now, and after it while it
    // is up (see _follow).
    _place(_clearance(bars: next.clearsBar));
    late final _Bar bar;
    bar = _Bar(
      next,
      text: next.resolve(context.l10n),
      persist: persist,
      label: label,
      onAction: action == null || label == null
          ? null
          : () {
              if (bar.answered) return;
              bar.answered = true;
              _leaving = true;
              action();
              _hide();
            },
    );
    final gone = _present(bar);
    _showing = next;
    _showingPersists = persist;
    // Whatever already waits takes its place once it has had its time.
    _yieldPending = _waiting.isNotEmpty;
    if (persist) {
      _held = _Countdown(_barTime, () {
        if (!mounted || !_yieldPending) return;
        _leaving = true;
        _hide();
      }, paused: _covered);
    }
    _checkCover();
    // Again once the frame that draws it is laid out.
    _watch();
    unawaited(
      gone.then((_) {
        if (mounted) _showNext();
      }),
    );
  }

  /// Draws [bar], on its way in, and answers once it has gone.
  Future<void> _present(_Bar bar) {
    final gone = _gone = Completer<void>();
    setState(() {
      _bar = bar;
      // One bar for every page that draws it, each its own element.
      _drawn = WaxMessageBar(
        message: bar.text,
        actionLabel: bar.onAction == null ? null : bar.label,
        onAction: bar.onAction,
        actionSemanticsId: bar.message.actionSemanticsId,
        onClose: bar.persist ? _hide : null,
        onDismiss: _remove,
        animation: _motion,
      );
    });
    _shownChanged();
    unawaited(_motion.forward(from: 0));
    return gone.future;
  }

  void _moved(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.completed:
        // Its time starts once it is up, and a bar that waits for its
        // action has none.
        final bar = _bar;
        if (bar != null && !bar.persist) {
          _airing ??= _Countdown(_barTime, () {
            if (_bar == bar) _hide();
          }, paused: _covered);
        }
      case AnimationStatus.dismissed:
        _drop();
      case AnimationStatus.forward || AnimationStatus.reverse:
        break;
    }
  }

  /// Takes the bar on screen off the way it came, or at once while
  /// accessible navigation is on.
  void _hide() {
    if (_bar == null || _motion.status.isDismissed) return;
    if (_motion.status == AnimationStatus.reverse) return;
    if (MediaQuery.accessibleNavigationOf(context)) {
      _motion.value = 0;
    } else {
      unawaited(_motion.reverse());
    }
  }

  /// Takes the bar on screen off at once: swiped away, dismissed by a
  /// screen reader, or cut for the next.
  void _remove() {
    if (_bar == null) return;
    if (_motion.status.isDismissed) {
      _drop();
    } else {
      _motion.value = 0;
    }
  }

  void _drop() {
    if (_bar == null) return;
    final gone = _gone;
    _gone = null;
    setState(() {
      _bar = null;
      _drawn = null;
    });
    _shownChanged();
    gone?.complete();
  }
}

/// A stopwatch for a message's time: the monotonic one, so a change of
/// the system's clock neither stretches nor ends it, or one on the
/// zone's clock where a test runs fake time.
@visibleForTesting
Stopwatch messageStopwatch() =>
    identical(clock, const Clock()) ? Stopwatch() : clock.stopwatch();

/// The animation a hero flight's [shuttle] flies under: that of Flutter's
/// hero overlay, the builder whose child is the shuttle itself, else
/// [route]'s.
@visibleForTesting
Animation<double> flightAnimation(
  BuildContext context,
  Widget shuttle,
  Animation<double> route,
) => switch (context.findAncestorWidgetOfExactType<AnimatedBuilder>()) {
  AnimatedBuilder(:final Animation<double> animation, :final child)
      when identical(child, shuttle) =>
    animation,
  _ => route,
};

/// A message's time on the bar, which stands still while it is paused.
///
/// Read from a clock, not counted in timer ticks: a browser runs a
/// background tab's timers about once a second, which would stretch a
/// count of short ticks tenfold.
class _Countdown {
  _Countdown(this._left, this._done, {bool paused = false}) {
    if (!paused) resume();
  }

  Duration _left;
  final VoidCallback _done;

  /// Running while its time does.
  Stopwatch? _running;
  Timer? _timer;
  var _over = false;

  /// Whether its time is still to run out, paused or not.
  bool get isActive => !_over;

  void pause() {
    final running = _running;
    if (running == null) return;
    _left -= running.elapsed;
    _running = null;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_over || _running != null) return;
    _running = messageStopwatch()..start();
    _timer = Timer(_left, _check);
  }

  void _check() {
    final left = _left - _running!.elapsed;
    if (left > Duration.zero) {
      _timer = Timer(left, _check);
      return;
    }
    cancel();
    _done();
  }

  void cancel() {
    _over = true;
    _running = null;
    _timer?.cancel();
    _timer = null;
  }
}

/// What tells the host above it how messages are drawn, known to it while
/// in the tree.
abstract class _DeclaredState<T extends StatefulWidget> extends State<T> {
  _ShellMessageHostState? _host;

  /// Off on a hidden tab and under a page that covers this one.
  var _inSight = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inSight = TickerMode.valuesOf(context).enabled;
    final host = context.findAncestorStateOfType<_ShellMessageHostState>();
    if (host != _host) {
      _host?._declared.remove(this);
      _host = host?.._declared.add(this);
    }
    _host?._declarationsChanged();
  }

  // Withdrawn while out of the tree, so no message is measured against
  // what is on its way out of it.
  @override
  void deactivate() {
    _host
      ?.._declared.remove(this)
      .._declarationsChanged();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _host
      ?.._declared.add(this)
      .._declarationsChanged();
  }
}

/// A page the shell's messages are drawn on. While one is up its bar is
/// drawn over [child] as a floating snack bar was drawn in the page's
/// Scaffold: along its foot, above the keyboard or else inside the view's
/// padding, inside the padding at its sides, in the page's theme, and
/// under whatever opens over the page. Every [WaxScaffold] under the host
/// is one; a page on a bare Scaffold declares its own. Of nested areas
/// only the outermost draws.
class ShellMessageArea extends StatefulWidget {
  const ShellMessageArea({required this.child, super.key});

  final Widget child;

  @override
  State<ShellMessageArea> createState() => _ShellMessageAreaState();
}

class _ShellMessageAreaState extends _DeclaredState<ShellMessageArea> {
  /// Whether this area draws the bar: no area around it does.
  var _draws = true;

  late _Insets _insets;

  /// The route this page is on, and the routes of the pages its navigator
  /// is nested in.
  ModalRoute<Object?>? _route;
  _Nest? _nest;

  /// Whether a flight has come to this page's copy since the page last
  /// went out of sight.
  var _flownTo = false;

  /// Bumped to draw this page's copy afresh.
  var _drawing = 0;

  /// This page's copy as its hero shows it, while it does.
  _CopyState? _copy;

  /// Whether this page drew a copy when last built.
  var _drawsCopy = false;

  /// The flights on their way to this page's copy.
  final _inbound = <_ShuttleState>{};

  /// This page's floating buttons, and where its copy is placed above
  /// them.
  final _floating = <_ShellMessageClearanceState>{};
  final _placers = <_AboveFloatingBox>{};

  /// Whether this page is a dialog's opened over a session, on the navigator
  /// around it, its host having left the messages to the session's: an
  /// imperative route, which goes with the page under it, rather than a
  /// page of the route table, such as a sign-in screen coming as the
  /// session goes.
  bool get _overSession {
    final host = _host;
    return host != null &&
        host._drawer != host &&
        _route != null &&
        _route!.settings is! Page<Object?>;
  }

  /// The host that draws this page's messages.
  _ShellMessageHostState? get _drawnBy => _overSession ? _host!._drawer : _host;

  /// Whether this page is the one in front: in sight, and its route and
  /// the routes around it current.
  bool get _inFront =>
      _inSight && (_route?.isCurrent ?? true) && (_nest?.current ?? true);

  /// Whether this page is in front and no route it is on or in is moving,
  /// so no flight can be on its way to it.
  bool get _atRest =>
      _inFront &&
      <ModalRoute<Object?>>[?_route, ...?_nest?.routes].every(
        (route) =>
            !(route.animation?.isAnimating ?? false) &&
            !(route.secondaryAnimation?.isAnimating ?? false),
      );

  /// Whether this page's copy is one a flight off it left hidden, with no
  /// flight coming back to it.
  bool get _stale =>
      _drawsCopy &&
      _inbound.isEmpty &&
      !_flownTo &&
      (_copy?._heroHides ?? false);

  /// Whether this page was in front when its dependencies last changed.
  var _wasInFront = false;

  @override
  void didChangeDependencies() {
    final wasInSight = _inSight;
    _insets = _insetsOf(context);
    _draws = context.findAncestorStateOfType<_ShellMessageAreaState>() == null;
    _route = ModalRoute.of(context);
    _nest = context.dependOnInheritedWidgetOfExactType<_Nest>();
    super.didChangeDependencies();
    if (wasInSight && !_inSight) _flownTo = false;
    final cameToFront = _inFront && !_wasInFront;
    _wasInFront = _inFront;
    // Shown again, or uncovered: a tab shown under a dialog comes to the
    // front only as the dialog closes.
    if (cameToFront || !wasInSight && _inSight) {
      // Nothing moving: drawn in the frame that shows it. Otherwise once
      // that frame's flights have started.
      if (_atRest && _stale) {
        _drawing++;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showCopy());
      }
    }
  }

  /// A flight off this page leaves its copy hidden until a flight comes
  /// back to it, which a page uncovered while another tab showed, or
  /// shown again under a cover, never brings: drawn afresh, if this page
  /// is the one in front.
  void _showCopy() {
    if (mounted && _inFront && _stale) setState(() => _drawing++);
  }

  /// Where a flight to this page's copy goes, as Material's own: noted,
  /// so the copy is left to it, and told to the host, which has every
  /// page's copy stand aside from the frame the flight is first drawn.
  RectTween _flight(Rect? begin, Rect? end) {
    _flownTo = true;
    _drawnBy?._flightTo(this);
    return MaterialRectArcTween(begin: begin, end: end);
  }

  /// A floating button on this page was laid out, came or went.
  void _floatingMoved() {
    for (final placer in _placers) {
      placer.markNeedsPaint();
    }
  }

  /// This page's box, once laid out.
  RenderBox? get _box {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  @override
  Widget build(BuildContext context) {
    final shown = context.dependOnInheritedWidgetOfExactType<_Shown>();
    final drawn = _overSession ? shown?.session : shown?.own;
    final message = drawn?.message;
    final bar = _draws ? drawn?.bar : null;
    _drawsCopy = bar != null && message != null;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        if (bar != null && message != null)
          _resting(
            _AboveFloating(
              page: this,
              // A hero, as Material's snack bar was: between two pages it
              // flies as one copy above both rather than fading out with
              // one and in with the other.
              child: KeyedSubtree(
                key: ValueKey(_drawing),
                child: Hero(
                  key: ObjectKey(message),
                  tag: message,
                  transitionOnUserGestures: true,
                  createRectTween: _flight,
                  flightShuttleBuilder: _inFlight,
                  child: _Copy(child: bar),
                ),
              ),
            ),
            _insets,
            drawn!.lift,
            right:
                context
                    .dependOnInheritedWidgetOfExactType<ShellMessageMargin>()
                    ?.right ??
                0,
          ),
      ],
    );
  }
}

/// The bar in flight between two pages, in the colours of the page it is
/// flying to.
Widget _inFlight(
  BuildContext flight,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext from,
  BuildContext to,
) => _Shuttle(
  page: to.findAncestorStateOfType<_ShellMessageAreaState>(),
  from: from.findAncestorStateOfType<_ShellMessageAreaState>(),
  animation: animation,
  direction: direction,
  child: InheritedTheme.captureAll(
    to,
    ((to.widget as Hero).child as _Copy).child,
  ),
);

/// The bar in flight from [from]'s copy to [page]'s, which draws it while
/// its host has it carry the bar (see [_ShellMessageHostState._carrier]).
class _Shuttle extends StatefulWidget {
  const _Shuttle({
    required this.page,
    required this.from,
    required this.animation,
    required this.direction,
    required this.child,
  });

  final _ShellMessageAreaState? page;
  final _ShellMessageAreaState? from;

  /// The flight's route animation, as it was started.
  final Animation<double> animation;
  final HeroFlightDirection direction;
  final Widget child;

  @override
  State<_Shuttle> createState() => _ShuttleState();
}

class _ShuttleState extends State<_Shuttle> {
  _ShellMessageHostState? _host;

  /// The flight's own animation, which a turn of the flight towards another
  /// page carries on, and its navigator.
  Animation<double>? _flying;
  NavigatorState? _navigator;

  /// How many navigators deep the flight is: a flight of a navigator
  /// around another is drawn above its pages.
  var _depth = 0;

  /// Whether the flight has not yet landed.
  var _inAir = true;

  /// The page it is flying to as last looked, which knows it is coming, and
  /// whether that page was still there.
  _ShellMessageAreaState? _bound;
  var _canCarry = true;
  var _awaitingFinger = false;

  /// The page the flight lands on: the one it set out from once it turned
  /// back, as a push a pop reversed.
  _ShellMessageAreaState? get _target {
    final status = widget.animation.status;
    final back = switch (widget.direction) {
      HeroFlightDirection.push => status == AnimationStatus.reverse,
      HeroFlightDirection.pop => status == AnimationStatus.forward,
    };
    return back ? widget.from : widget.page;
  }

  /// Whether the flight is where it can be seen: a hidden tab's flights
  /// stand still, out of sight.
  bool get _inSight {
    var shown = true;
    context.visitAncestorElements((element) {
      if (element.widget case TickerMode(enabled: false)) shown = false;
      return shown;
    });
    return shown;
  }

  @override
  void initState() {
    super.initState();
    _host = widget.page?._drawnBy ?? widget.from?._drawnBy;
    _navigator = Navigator.maybeOf(context);
    for (NavigatorState? at = _navigator; at != null; _depth++) {
      at = at.context.findAncestorStateOfType<NavigatorState>();
    }
    final flying = _flying = flightAnimation(context, widget, widget.animation);
    flying
      ..addListener(_moved)
      ..addStatusListener(_statusChanged);
    _aim();
    _host?._took(this);
  }

  @override
  void didUpdateWidget(_Shuttle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_aim()) _host?._announced.remove(_bound);
  }

  /// Tells the page it is flying to that it is coming, and any it no longer
  /// is that it is not; whether that changed.
  bool _aim() {
    final target = _inAir ? _target : null;
    _canCarry = target?.mounted ?? true;
    if (target == _bound) return false;
    _bound?._inbound.remove(this);
    _bound = target
      ?.._inbound.add(this)
      .._flownTo = true;
    return true;
  }

  /// The flight turned back, or the page it flies to is gone, a back
  /// gesture or a pop having taken it away: it can no longer carry the bar.
  void _moved() {
    final could = _canCarry;
    _aim();
    if (could != _canCarry) _host?._flightsChanged();
  }

  void _statusChanged(AnimationStatus status) {
    if (status.isAnimating) return _moved();
    // As the flight itself: a gesture's ends once the finger lifts.
    final navigator = _navigator;
    if (navigator != null && navigator.userGestureInProgress) {
      if (!_awaitingFinger) {
        _awaitingFinger = true;
        navigator.userGestureInProgressNotifier.addListener(_fingerLifted);
      }
      return;
    }
    _land();
  }

  void _fingerLifted() {
    final navigator = _navigator!;
    if (navigator.userGestureInProgress) return;
    _awaitingFinger = false;
    navigator.userGestureInProgressNotifier.removeListener(_fingerLifted);
    if (!(_flying?.isAnimating ?? false)) _land();
  }

  void _land() {
    if (!_inAir) return;
    _inAir = false;
    _aim();
    _host?._landed(this);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // Gone without landing, as when its navigator goes: in a build, so the
  // rest are told after it.
  @override
  void deactivate() {
    if (_inAir) {
      _inAir = false;
      _aim();
      _host?._landed(this);
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _flying
      ?..removeListener(_moved)
      ..removeStatusListener(_statusChanged);
    if (_awaitingFinger) {
      _navigator?.userGestureInProgressNotifier.removeListener(_fingerLifted);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Built again as its tab is hidden or shown.
    TickerMode.valuesOf(context);
    final host = _host;
    return host == null || identical(host._carrier, this)
        ? widget.child
        : const SizedBox.shrink();
  }
}

/// A page's copy of the bar, which tells its page whether its hero shows
/// it, and stands aside while a flight carries the bar.
class _Copy extends StatefulWidget {
  const _Copy({required this.child});

  final Widget child;

  @override
  State<_Copy> createState() => _CopyState();
}

class _CopyState extends State<_Copy> {
  _ShellMessageAreaState? _area;

  /// Whether this copy's hero hides it: in flight, or left behind by one.
  bool get _heroHides =>
      context.findAncestorWidgetOfExactType<Offstage>()?.offstage ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final area = context.findAncestorStateOfType<_ShellMessageAreaState>();
    if (area != _area) {
      if (_area?._copy == this) _area!._copy = null;
      _area = area?.._copy = this;
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_area?._copy == this) _area!._copy = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Built again as its hero starts or ends a flight, so a flight that
    // ends with no word to the host still leaves the copy right.
    TickerMode.valuesOf(context);
    final aside = _area?._drawnBy?._flying ?? false;
    // Laid out as ever, so a flight to or from it measures the bar.
    return IgnorePointer(
      ignoring: aside,
      child: Opacity(opacity: aside ? 0 : 1, child: widget.child),
    );
  }
}

/// Places a page's copy of the bar above the page's floating buttons as
/// they are laid out, so it moves on the frame one comes or goes, as a
/// floating snack bar did in Material's Scaffold, rather than through the
/// button's entrance.
class _AboveFloating extends SingleChildRenderObjectWidget {
  const _AboveFloating({required this.page, required super.child});

  final _ShellMessageAreaState page;

  @override
  _AboveFloatingBox createRenderObject(BuildContext context) =>
      _AboveFloatingBox(page);

  @override
  void updateRenderObject(BuildContext context, _AboveFloatingBox box) =>
      box.page = page;
}

class _AboveFloatingBox extends RenderProxyBox {
  _AboveFloatingBox(this._page);

  _ShellMessageAreaState _page;
  set page(_ShellMessageAreaState page) {
    if (identical(page, _page)) return;
    if (attached) {
      _page._placers.remove(this);
      page._placers.add(this);
    }
    _page = page;
    markNeedsPaint();
  }

  /// How far above where it is laid out the copy is drawn.
  double _rise = 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _page._placers.add(this);
  }

  @override
  void detach() {
    _page._placers.remove(this);
    super.detach();
  }

  /// How far the bottom of this box reaches below the highest of its
  /// page's floating buttons, as they are laid out.
  double _measure() {
    if (_page._floating.isEmpty) return 0;
    final frame = _page._box;
    final bottom = frame == null ? null : _laidOutTop(this, frame);
    if (frame == null || bottom == null) return 0;
    var rise = 0.0;
    for (final floating in _page._floating) {
      final box = floating.context.findRenderObject();
      final top = box is RenderBox ? _laidOutTop(box, frame) : null;
      if (top != null) rise = math.max(rise, bottom + size.height - top);
    }
    return rise;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final rise = _measure();
    if (rise != _rise) {
      _rise = rise;
      markNeedsSemanticsUpdate();
    }
    super.paint(context, offset.translate(0, -_rise));
  }

  // Where the copy is drawn, which is above this box once it rises.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!(Offset(0, -_rise) & size).contains(position)) return false;
    if (!hitTestChildren(result, position: position)) return false;
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: Offset(0, -_rise),
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) =>
      transform.multiply(Matrix4.translationValues(0, -_rise, 0));
}

/// [box]'s top in [frame] as laid out, apart from any transform painted
/// over it (a floating button's entrance scales it); null while it is not
/// laid out under [frame].
double? _laidOutTop(RenderBox box, RenderBox frame) {
  if (!box.attached || !box.hasSize) return null;
  var top = 0.0;
  RenderObject? node = box;
  while (node != null && !identical(node, frame)) {
    switch (node.parentData) {
      case BoxParentData(:final offset):
        top += offset.dy;
      // A proxy lays its child out where it is itself.
      case _ when node.parent is RenderProxyBox:
        break;
      default:
        return box.localToGlobal(Offset.zero, ancestor: frame).dy;
    }
    node = node.parent;
  }
  return node == null ? null : top;
}

/// Around a navigator nested in a page: a page in it is in front only
/// while the page around its navigator is, and moves when that page does.
class ShellMessageNest extends StatelessWidget {
  const ShellMessageNest({required this.child, super.key});

  final Widget child;

  /// Whether [context]'s screen is what the user sees: its tickers run and
  /// no route covers it, on its own navigator or on any it is nested in.
  static bool showing(BuildContext context) =>
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.isCurrentOf(context) ?? true) &&
      (context.dependOnInheritedWidgetOfExactType<_Nest>()?.current ?? true);

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final outer = context.dependOnInheritedWidgetOfExactType<_Nest>();
    return _Nest(
      routes: <ModalRoute<Object?>>[?route, ...?outer?.routes],
      current: (route?.isCurrent ?? true) && (outer?.current ?? true),
      child: child,
    );
  }
}

/// The routes of the pages a navigator is nested in, innermost first.
class _Nest extends InheritedWidget {
  const _Nest({
    required this.routes,
    required this.current,
    required super.child,
  });

  final List<ModalRoute<Object?>> routes;

  /// Whether every one of them is current.
  final bool current;

  @override
  bool updateShouldNotify(_Nest oldWidget) =>
      current != oldWidget.current || !listEquals(routes, oldWidget.routes);
}

/// Keeps the shell's messages off a bar along the bottom of a screen: one
/// up while the bar is in the tree and in sight is drawn above it, as a
/// snack bar is drawn above a bottom navigation bar, and goes back down
/// once the bar has gone or is out of sight.
///
/// Measured after each frame, so a bar that wraps on a narrow screen is
/// cleared at the height it has then.
class ShellMessageClearance extends StatefulWidget {
  const ShellMessageClearance({required this.child, super.key})
    : pending = false,
      _standsIn = false,
      _floating = false;

  /// A page's floating button, which every message rests above, as a
  /// floating snack bar rested above Material's, one declining the lift
  /// of a bar included.
  const ShellMessageClearance._floating(this.child)
    : pending = false,
      _standsIn = false,
      _floating = true;

  /// Stands in for a bar still to be drawn while [pending]: a message
  /// already clear of a bar stays where it is, rather than dropping for
  /// the moment a screen spends between one bar and the next. Its [child]
  /// is not measured.
  const ShellMessageClearance.pending({
    required this.pending,
    required this.child,
    super.key,
  }) : _standsIn = true,
       _floating = false;

  final Widget child;

  /// Whether a bar is on its way to where this stands.
  final bool pending;

  /// False for the bar itself.
  final bool _standsIn;

  /// Whether this is a page's floating button rather than a bar.
  final bool _floating;

  @override
  State<ShellMessageClearance> createState() => _ShellMessageClearanceState();
}

class _ShellMessageClearanceState
    extends _DeclaredState<ShellMessageClearance> {
  /// The page this bar is on, the area that draws messages over it.
  _ShellMessageAreaState? _page;

  /// Whether this asks anything of a message now.
  bool get _declares => _inSight && (!widget._standsIn || widget.pending);

  /// Whether this asks the host to lift a message that clears [bars] or
  /// not: a bar only one that does. A floating button asks its page, which
  /// places every message above it as it is laid out (see [_AboveFloating]).
  bool _asks({required bool bars}) => bars && !widget._floating;

  @override
  void didChangeDependencies() {
    final page = context.findRootAncestorStateOfType<_ShellMessageAreaState>();
    if (widget._floating && page != _page) {
      _page?._floating.remove(this);
      page?._floating.add(this);
    }
    _page = page;
    super.didChangeDependencies();
  }

  @override
  void deactivate() {
    if (widget._floating) _page?._floating.remove(this);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    if (widget._floating) _page?._floating.add(this);
  }

  @override
  void didUpdateWidget(ShellMessageClearance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pending != widget.pending ||
        oldWidget._standsIn != widget._standsIn ||
        oldWidget._floating != widget._floating) {
      _host?._declarationsChanged();
    }
  }

  /// How far above where a message rests on its page this bar's top is
  /// now; null while there is no bar to measure, one still to come or not
  /// yet laid out, or no page to measure it on.
  double? _rise() {
    if (widget._standsIn) return null;
    final page = _page;
    final frame = page?._box;
    final bar = context.findRenderObject();
    if (page == null ||
        frame == null ||
        bar is! RenderBox ||
        !bar.attached ||
        !bar.hasSize) {
      return null;
    }
    final top = bar.localToGlobal(Offset.zero, ancestor: frame).dy;
    final rests = frame.size.height - _keptAbove(page._insets);
    // Never past the middle of the page: a bar that high is not along the
    // bottom, and a message lifted further could leave the screen.
    return (rests - top).clamp(0.0, frame.size.height / 2);
  }

  @override
  Widget build(BuildContext context) => widget._floating
      ? _LaidOut(onChange: () => _page?._floatingMoved(), child: widget.child)
      : widget.child;
}

/// Says when its child is laid out, comes or goes.
class _LaidOut extends SingleChildRenderObjectWidget {
  const _LaidOut({required this.onChange, required super.child});

  final VoidCallback onChange;

  @override
  _LaidOutBox createRenderObject(BuildContext context) => _LaidOutBox(onChange);

  @override
  void updateRenderObject(BuildContext context, _LaidOutBox box) =>
      box.onChange = onChange;
}

class _LaidOutBox extends RenderProxyBox {
  _LaidOutBox(this.onChange);

  VoidCallback onChange;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    onChange();
  }

  @override
  void detach() {
    onChange();
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    onChange();
  }
}
