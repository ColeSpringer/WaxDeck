import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_data/waxdeck_data.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../admin/admin_providers.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../media_view.dart';
import '../settings/client_prefs.dart';
import '../shell/async_box_face.dart';
import '../shell/in_flight.dart';
import '../shell/navigation_history.dart';
import '../shell/pending_actions.dart';
import '../shell/router.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import '../shell/shortcuts.dart';
import 'review_controller.dart';
import 'review_entry_screen.dart';

/// The review surface: the queue, with one entry beside it where there
/// is room and in place of it where there is not. Both `/review`
/// locations land here, so an entry keeps its own URL either way.
class ReviewSurface extends StatelessWidget {
  const ReviewSurface({super.key, this.openEntryId});

  final String? openEntryId;

  /// The narrowest the list may be squeezed to and still read as a
  /// queue, and the widest it grows to on its own.
  static const listMin = 280.0;
  static const listMax = 380.0;

  /// What the entry beside it needs, asked of the entry rather than
  /// guessed: the diff table's own minimum plus the chrome between it
  /// and the pane's edge. Below this the table's horizontal scroller
  /// takes over, which is the crowding this threshold exists to keep
  /// the reviewer out of.
  static const paneMin = ReviewEntryView.minWidth;

  /// The narrowest content pane that holds both.
  ///
  /// Derived from what the *entry* needs rather than from what the list
  /// wants, which is the change: the old threshold added 340 to a fixed
  /// 380 list, so the first window wide enough to split gave the
  /// submission 340 - well inside the table's own minimum, and a
  /// horizontal scrollbar under the thing being read. Every window that
  /// gets two panes can now hold the table without one.
  static const _twoPaneMinWidth = listMin + WaxSplitter.hitWidth + paneMin;

  @override
  Widget build(BuildContext context) {
    // Measured, not the window's size class: the shell sidebar and the
    // console list take ~500px before this screen starts, and the queue
    // and the entry take the window's side insets inside theirs.
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane =
            constraints.maxWidth - MediaQuery.paddingOf(context).horizontal >=
            _twoPaneMinWidth;
        if (openEntryId != null && !twoPane) {
          return ReviewEntryScreen(entryId: openEntryId!);
        }
        return ReviewScreen(openEntryId: twoPane ? openEntryId : null);
      },
    );
  }
}

/// Where the reviewer put the seam, in whole pixels; zero is "wherever
/// the layout puts it", which is what a fresh device reads and what the
/// double-tap reset writes back.
///
/// Per device, stored beside the sidebar's own fold rather than on the
/// account: a seam is a fact about the window it was dragged in, and the
/// screen clamps whatever comes back against the room it actually has.
class ReviewListWidth extends IntSetting {
  @override
  String get settingKey => ClientSettingKeys.reviewListWidth;

  @override
  int get defaultValue => 0;

  @override
  int get minValue => 0;

  /// A sanity ceiling rather than a layout bound, and deliberately past
  /// any panel a seam could be dragged across: [IntSetting.set] clamps
  /// writes as well as reads, so a bound near a real width would freeze
  /// the seam under a still-moving pointer on a wide enough screen. The
  /// screen bounds this against the room it actually has, every frame.
  @override
  int get maxValue => 32000;
}

final reviewListWidthProvider = NotifierProvider<ReviewListWidth, int>(
  ReviewListWidth.new,
);

/// The metadata review queue: filterable, cursor paged, keyboard-first.
/// j/k move, a/s/u decide, e opens, Escape leaves. Long-press a row or
/// use the select button for bulk decisions.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.openEntryId});

  /// The entry drawn in the pane beside the list. Only ever set above
  /// sidebar width, where there is a pane to draw it in.
  final String? openEntryId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

/// Every decision holds its entries' locks in [pendingActionsProvider],
/// shared with the pane: an entry's own (its keys) and a bulk one, which
/// also runs here, one at a time, keyed by [_bulkWork].
class _ReviewScreenState extends ConsumerState<ReviewScreen>
    with InFlight<ReviewScreen, String> {
  /// Fixed row height so keyboard selection can scroll by arithmetic
  /// instead of hunting for offscreen render objects.
  static const _rowExtent = 76.0;

  /// The list's own width once the pane is beside it.
  ///
  /// A third of the room, bounded, rather than a fixed 380: the pane is
  /// where the reading happens, so the majority goes to the submission
  /// somebody opened - which at the width this was reported at meant a
  /// queue of one-line rows holding 380 while the files under review
  /// had 343.
  ///
  /// A seam dragged by hand outranks that and is allowed past [listMax],
  /// as far as the entry's own floor: the default is a guess about what
  /// somebody wants, and a drag is not.
  ///
  /// [stored] is read in `build` and passed down rather than watched
  /// here: this runs from a `LayoutBuilder`, which builds during layout
  /// rather than during the build that owns this ref.
  ///
  /// [available] here and in [_listMax] is the room inside the side
  /// insets, and the widths are the list's own inside them.
  double _listWidth(double available, int stored) {
    final room = available - WaxSplitter.hitWidth;
    final wanted =
        _dragging ??
        (stored > 0
            ? stored.toDouble()
            : (room / 3).clamp(ReviewSurface.listMin, ReviewSurface.listMax));
    return wanted.clamp(ReviewSurface.listMin, _listMax(available));
  }

  /// Where a drag in flight has the seam, so the panes follow the
  /// pointer without a preference being written down per frame. Null
  /// outside a gesture, when the stored width is the answer again.
  double? _dragging;

  /// The widest the list may be drawn at this size, which is whatever
  /// leaves the entry its floor. Never below [ReviewSurface.listMin]:
  /// the surface only draws two panes above the threshold, and clamping
  /// to a smaller maximum than minimum throws.
  double _listMax(double available) =>
      (available - WaxSplitter.hitWidth - ReviewSurface.paneMin).clamp(
        ReviewSurface.listMin,
        double.infinity,
      );

  final _scroll = ScrollController();

  /// Index of the keyboard-selected row; -1 before the first j/k.
  var _selected = -1;

  /// Multi-select mode with the checked entry ids.
  var _selecting = false;
  final _checked = <String>{};

  /// Where back goes, and the router that goes there, held from the
  /// start: a decision can land after this screen has gone, and still has
  /// to be forgotten.
  WaxHistory? _history;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    _history = ref.read(waxHistoryProvider);
    _router = GoRouter.maybeOf(context);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<ReviewEntry> get _entries =>
      ref.read(reviewQueueProvider).value?.entries ?? const [];

  void _move(int delta) {
    final entries = _entries;
    if (entries.isEmpty) return;
    setState(() {
      _selected = (_selected + delta).clamp(0, entries.length - 1);
    });
    _ensureVisible(_selected);
    if (_selected >= entries.length - 3) {
      ref.read(reviewQueueProvider.notifier).loadMore();
    }
  }

  void _ensureVisible(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final target = index * _rowExtent;
    final top = position.pixels;
    final bottom = top + position.viewportDimension - _rowExtent;
    final double? to = target < top
        ? target
        : target > bottom
        ? target - position.viewportDimension + _rowExtent
        : null;
    if (to == null) return;
    _scroll.animateTo(
      to.clamp(0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  Future<void> _decideSelected(String action) async {
    final entries = _entries;
    if (_selected < 0 || _selected >= entries.length) return;
    final entry = entries[_selected];
    // Decided and being moved off: its row reads pending until the queue
    // has read again.
    if (entry.status != 'pending' ||
        entry.identifying ||
        _leaving == entry.id) {
      return;
    }
    // Opened, for the decision to be made where the duplicates can be
    // seen. Where they already are, opening it again would do nothing,
    // so the key says what decides it instead.
    if (_heldBack(entry, action)) {
      if (widget.openEntryId == entry.id) {
        ref
            .read(shellMessengerProvider)
            .show(context.l10n.reviewDecideHeldInPane);
      } else {
        _open(entry);
      }
      return;
    }
    // The pane offers no approve for an audiobook, and the server refuses it.
    if (action == 'approve' &&
        reviewEntryMedium(ref, entry.id, entry.origin, entry.mediaType) ==
            MediaType.audiobook) {
      ref
          .read(shellMessengerProvider)
          .show(context.l10n.reviewApproveNotForAudiobook);
      return;
    }
    // `a` on the row the pane is showing approves what the pane has
    // selected, or the two controls decide different releases.
    await _decide(
      entry,
      action,
      candidateMbid: action == 'approve'
          ? ref.read(selectedCandidateProvider(entry.id))
          : null,
    );
  }

  /// Decides [entry]; its medium is read again at every send, a retry
  /// included, so it is never one the entry's switch no longer offers.
  Future<void> _decide(
    ReviewEntry entry,
    String action, {
    String? candidateMbid,
  }) => ref.read(pendingActionsProvider.notifier).runAll(
    [
      PendingAction.reviewEntry(entry.id),
      PendingAction.reviewAction(entry.id, action),
    ],
    () async {
      final entryId = entry.id;
      final mediaType = reviewDecisionMedium(
        ref,
        entryId,
        entry.origin,
        entry.mediaType,
        action,
      );
      final l10n = context.l10n;
      final messenger = ref.read(shellMessengerProvider);
      final container = ProviderScope.containerOf(context, listen: false);
      final open = widget.openEntryId == entryId;
      try {
        final decided = await ref
            .read(reviewQueueProvider.notifier)
            .decide(
              entryId,
              action,
              candidateMbid: candidateMbid,
              mediaType: mediaType,
              useSuggested: reviewDecisionUseSuggested(ref, entryId, action),
            );
        // A key on the row the pane shows moves the pane as its buttons
        // do, the pane having come to that row meanwhile included.
        if (open || widget.openEntryId == entryId) {
          showReviewDecided(container, l10n, entryId, decided);
          unawaited(_follow(entryId));
          return;
        }
        forgetDecided(_history, [entryId]);
        if (decided.warnings.isNotEmpty) {
          // The server's own words: a warning names the file or the field
          // it is about, which no table sentence can.
          messenger.show(decided.warnings.join('\n'));
        }
      } on WaxDeckApiException catch (e) {
        // A `conflict` names the file the library cannot take, which the
        // table's "something changed first" would hide.
        showRefusal(
          messenger,
          l10n,
          explainRefusal(l10n, e),
          refused: {entryId: e.code},
          mounted: () => mounted,
          retry: (_) => _decide(entry, action, candidateMbid: candidateMbid),
        );
      }
    },
  );

  /// Whether the list leaves [action] on [entry] to its pane: the pane
  /// holds approving and marking unofficial back from a unit whose files
  /// the library already has, and a row only knows that some matched.
  static bool _heldBack(ReviewEntry entry, String action) =>
      entry.status == 'pending' &&
      entry.duplicateCount > 0 &&
      const {'approve', 'unofficial'}.contains(action);

  /// Whether a bulk [action] leaves [entry] to its pane for its medium: a
  /// bulk call carries none, so an entry the pane switched away from its
  /// own is decided there, and the pane offers no approve for an audiobook.
  bool _bulkMediumHeld(ReviewEntry entry, String action) {
    if (entry.status != 'pending') return false;
    final medium = reviewDecisionMedium(
      ref,
      entry.id,
      entry.origin,
      entry.mediaType,
      action,
    );
    if (medium == null) return false;
    return medium != entry.mediaType ||
        (action == 'approve' && medium == MediaType.audiobook);
  }

  /// How many of the server's warnings one bulk snackbar spells out.
  static const _bulkWarningLines = 3;

  /// The in-flight key of a bulk [action], apart from every entry id.
  static String _bulkWork(String action) => 'bulk-$action';

  Future<void> _decideBulk(String action, [List<String>? only]) {
    final chosen = only ?? _checked.toList();
    if (chosen.isEmpty) return Future.value();
    return runAs(_bulkWork(action), () => _sendBulk(action, chosen, only));
  }

  Future<void> _sendBulk(
    String action,
    List<String> chosen,
    List<String>? only,
  ) {
    // What the a and u keys open rather than decide stays undecided
    // here, and is counted: each is for its own pane.
    final duplicates = {
      for (final entry in _entries)
        if (_heldBack(entry, action)) entry.id,
    };
    final medium = {
      for (final entry in _entries)
        if (!duplicates.contains(entry.id) && _bulkMediumHeld(entry, action))
          entry.id,
    };
    final ids = [
      for (final id in chosen)
        if (!duplicates.contains(id) && !medium.contains(id)) id,
    ];
    final held = (
      duplicates: chosen.where(duplicates.contains).length,
      medium: chosen.where(medium.contains).length,
    );
    // Every entry it sends, or none: one whose own decision is out holds
    // the whole bulk back rather than going twice.
    return ref.read(pendingActionsProvider.notifier).runAll([
      for (final id in ids) PendingAction.reviewEntry(id),
    ], () => _sendClaimed(action, ids, held, only));
  }

  /// Sends [ids] and says how it went, [held] counting the entries held
  /// back for their panes, by the reason each is.
  Future<void> _sendClaimed(
    String action,
    List<String> ids,
    ({int duplicates, int medium}) held,
    List<String>? only,
  ) async {
    final l10n = context.l10n;
    final messenger = ref.read(shellMessengerProvider);
    final shown = widget.openEntryId;
    try {
      final outcomes = ids.isEmpty
          ? const <ReviewBulkOutcome>[]
          : await ref
                .read(reviewQueueProvider.notifier)
                .decideBulk(ids, action);
      final failed = [
        for (final o in outcomes)
          if (!o.ok) o,
      ];
      // Worded as the single decide words them, and said where the
      // failures say one thing: the one entry that failed, or a busy
      // catalog behind all of them. Several reasons leave the count.
      final reasons = <String>{
        for (final o in failed)
          explainRefusal(
            l10n,
            WaxDeckApiException(code: o.code ?? '', message: o.error ?? ''),
          ),
      }..remove('');
      final warnings = [for (final o in outcomes) ...o.warnings];
      showRefusal(
        messenger,
        l10n,
        [
          if (outcomes.isNotEmpty)
            failed.isEmpty
                ? l10n.reviewDecidedCount(outcomes.length)
                : l10n.reviewDecidedSomeFailed(
                    outcomes.length - failed.length,
                    failed.length,
                  ),
          if (reasons.length == 1) reasons.single,
          if (held.duplicates > 0)
            l10n.reviewBulkHeldDuplicates(held.duplicates),
          if (held.medium > 0) l10n.reviewBulkHeldMedium(held.medium),
          ...warnings.take(_bulkWarningLines),
          if (warnings.length > _bulkWarningLines)
            l10n.reviewBulkMoreWarnings(warnings.length - _bulkWarningLines),
        ].join('\n'),
        refused: {for (final o in failed) o.entryId: o.code},
        mounted: () => mounted,
        retry: (again) => _decideBulk(action, again),
      );
      // The pane leaves an entry the bulk took, for one it did not: the
      // one it shows now, which may not be the one it showed at the send.
      // With this screen gone, the one it showed is what is left of it.
      final took = {
        for (final o in outcomes)
          if (o.ok) o.entryId,
      };
      final open = mounted ? widget.openEntryId : shown;
      if (open != null && took.contains(open)) {
        unawaited(_follow(open, gone: took));
      } else {
        forgetDecided(_history, took);
      }
      // Only for the decision somebody started: a Retry sends what an
      // earlier selection left, and the selection standing by then is
      // somebody's next one.
      if (only != null || !mounted) return;
      setState(() {
        _selecting = false;
        _checked.clear();
      });
    } on WaxDeckApiException catch (e) {
      messenger.show(explainError(l10n, e));
    }
  }

  void _openSelected() {
    final entries = _entries;
    if (_selected < 0 || _selected >= entries.length) return;
    _open(entries[_selected]);
  }

  void _open(ReviewEntry entry) {
    context.go(WaxRoute.reviewEntry(entry.id));
  }

  void _escape() {
    if (_selecting) {
      setState(() {
        _selecting = false;
        _checked.clear();
      });
      return;
    }
    // One page spans both locations, so leaving the entry is a move
    // rather than a pop.
    if (widget.openEntryId != null) context.go(WaxRoute.review);
  }

  void _toggleChecked(ReviewEntry entry) {
    setState(() {
      if (!_checked.add(entry.id)) _checked.remove(entry.id);
    });
  }

  /// The entry the pane opened that the cursor last moved to.
  String? _followed;

  /// The open entry's row at the last build, or -1 where it had none.
  var _openAt = -1;

  /// Keeps the cursor on a row that exists, and brings it to each entry
  /// the pane opens, once: j and k move it on from there. Deciding the
  /// last row shortens the queue under it, and a tap has to move it or
  /// the next j resumes from somewhere else. A cursor on the open row
  /// stays on it when rows arrive above, or the keys would decide
  /// another entry than the pane shows.
  void _syncSelection(List<ReviewEntry> entries) {
    final open = widget.openEntryId;
    final index = open == null
        ? -1
        : entries.indexWhere((entry) => entry.id == open);
    final was = _openAt;
    _openAt = index;
    if (open == null) {
      _followed = null;
    } else if (open != _followed) {
      if (index >= 0) {
        _followed = open;
        if (index != _selected) {
          _later(() => _selected = index);
          return;
        }
      }
    } else if (index >= 0 && was >= 0 && index != was && _selected == was) {
      _later(() => _selected = index);
      return;
    }
    if (_selected >= entries.length) {
      // Onto the last row rather than off the end: the reviewer was
      // working down the queue and the next thing they press should
      // decide something.
      _later(() => _selected = entries.length - 1);
    }
  }

  /// The entry [_aroundIn] was last drawn holding.
  String? _aroundOf;

  /// The list as last drawn holding the open entry, around which the pane
  /// goes once that entry is decided here (see [_nearest]). Kept from
  /// every draw rather than taken as a decision starts, because the pane's
  /// buttons decide without this screen; left alone once the entry drops
  /// out, which is the decision landing.
  List<ReviewEntry> _aroundIn = const [];

  /// After [_syncSelection], which leaves the open entry's row in
  /// [_openAt].
  void _recordAround(List<ReviewEntry> entries) {
    final open = widget.openEntryId;
    if (_openAt >= 0) {
      _aroundOf = open;
      _aroundIn = entries;
    } else if (open != _aroundOf) {
      _aroundOf = open;
      _aroundIn = const [];
    }
  }

  /// The rows around [entryId] in [_aroundIn], nearest first: those after
  /// it, then those before.
  List<String> _nearest(String entryId) {
    final entries = _aroundIn;
    final at = entries.indexWhere((entry) => entry.id == entryId);
    if (at < 0) return const [];
    return [
      for (var i = at + 1; i < entries.length; i++) entries[i].id,
      for (var i = at - 1; i >= 0; i--) entries[i].id,
    ];
  }

  /// The entry the pane is moving off, decided here, while the queue
  /// reads again.
  String? _leaving;

  /// Moves the pane off [decided], decided here: to the nearest row
  /// around it that the queue still holds once read again, else to the
  /// bare queue. Never onto [gone], what the same decision also took,
  /// and not at all when the pane has moved meanwhile.
  ///
  /// After the read rather than before it: the cursor is an index, and
  /// moving on the old rows would leave it on the row the refetch
  /// shifts under it. The pane draws the decided entry meanwhile, Revert
  /// and all, which is then the confirmation's undo: a reverted entry is
  /// decided for good, so it moves on all the same.
  Future<void> _follow(String decided, {Set<String> gone = const {}}) async {
    if (!mounted || widget.openEntryId != decided) {
      return _offScreen(decided, gone);
    }
    final around = _aroundOf == decided ? _nearest(decided) : const <String>[];
    setState(() => _leaving = decided);
    final List<ReviewEntry> held;
    try {
      held = await _landedQueue();
    } finally {
      if (mounted && _leaving == decided) setState(() => _leaving = null);
    }
    if (!mounted || widget.openEntryId != decided) {
      return _offScreen(decided, gone);
    }
    final ids = {for (final entry in held) entry.id}..removeAll(gone);
    final next = around.where(ids.contains).firstOrNull;
    await leaveDecided(
      context,
      decided,
      next == null ? WaxRoute.review : WaxRoute.reviewEntry(next),
      inPlace: next != null,
      alsoDecided: gone,
    );
  }

  /// Forgets [decided] and [gone], for a pane no longer on [decided]. Where
  /// this screen has gone and what took its place still shows [decided] (a
  /// window narrowed to one pane), that leaves it for the queue, as a
  /// decision made there would.
  Future<void> _offScreen(String decided, Set<String> gone) async {
    final host = mounted
        ? null
        : _router?.routerDelegate.navigatorKey.currentContext;
    if (host == null) {
      forgetDecided(_history, {decided, ...gone});
      return;
    }
    await leaveDecided(host, decided, WaxRoute.review, alsoDecided: gone);
  }

  /// The queue once the read a decision started has landed, or as it
  /// stands when that read fails. Not the first state to stop loading: a
  /// next page that lands ahead of that read is one, with the rows from
  /// before the decision.
  ///
  /// Listened to on the container meanwhile: this screen can go before
  /// the read lands (a window narrowed to one pane, a move elsewhere),
  /// and a queue nobody listens to reads nothing.
  Future<List<ReviewEntry>> _landedQueue() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final sub = container.listen(reviewQueueProvider, (_, _) {});
    try {
      final queue = container.read(reviewQueueProvider.notifier);
      return (await queue.refreshed())?.entries ?? const [];
    } finally {
      sub.close();
    }
  }

  /// Called from `build`, where `setState` is not allowed.
  void _later(VoidCallback move) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(move);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final queue = ref.watch(reviewQueueProvider);
    final seamAt = ref.watch(reviewListWidthProvider);
    final pending = ref.watch(pendingActionsProvider);
    final l10n = context.l10n;
    _syncSelection(queue.value?.entries ?? const []);
    _recordAround(queue.value?.entries ?? const []);
    // Surface a failed "load more": the queue keeps its rows, so the
    // failure is otherwise invisible. Firing on the flag's rising edge
    // shows one notice per failure, and scrolling again retries.
    ref.listen(reviewQueueProvider, (prev, next) {
      final failedNow = next.value?.loadError ?? false;
      final failedBefore = prev?.value?.loadError ?? false;
      if (failedNow && !failedBefore) {
        ref.read(shellMessengerProvider).show(l10n.reviewLoadMoreFailed);
      }
    });
    return AppShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyJ): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.keyK): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.keyA): () =>
            _decideSelected('approve'),
        const SingleActivator(LogicalKeyboardKey.keyS): () =>
            _decideSelected('skip'),
        const SingleActivator(LogicalKeyboardKey.keyU): () =>
            _decideSelected('unofficial'),
        const SingleActivator(LogicalKeyboardKey.keyE): _openSelected,
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
      },
      child: WaxScaffold(
        title: l10n.reviewTitle,
        largeTitle: false,
        semanticsId: SemanticsIds.adminReview,
        onBack: () => context.back(),
        backSemanticsId: SemanticsIds.navBack,
        actions: <Widget>[
          const _MatchingModeMenu(),
          WaxIconButton(
            glyph: _selecting ? WaxIcons.close : WaxIcons.check,
            label: _selecting ? l10n.reviewSelectLeave : l10n.reviewSelectEnter,
            active: _selecting,
            semanticsId: SemanticsIds.reviewSelectToggle,
            onPressed: () => setState(() {
              _selecting = !_selecting;
              if (!_selecting) _checked.clear();
            }),
          ),
        ],
        // The page's own foot bar, so the fill above it is handed none of
        // the bottom inset.
        bottom: _selecting
            ? _BulkBar(
                count: _checked.length,
                // Held while any entry it would send has a decision out,
                // its own included.
                busy:
                    busy ||
                    _checked.any(
                      (id) => pending.contains(PendingAction.reviewEntry(id)),
                    ),
                busyBy: (action) => busyBy(_bulkWork(action)),
                onDecide: _decideBulk,
              )
            : null,
        // A fill, not a body: the list needs a bounded height and a scroll
        // position of its own for j/k to move by arithmetic. Each part
        // takes the window's insets on the edges it stands against: the
        // chips both sides, the list its start and foot and, alone, its
        // end, the pane its end and foot.
        fill: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: sizeClass.gutter.left,
                  vertical: WaxSpace.s8,
                ),
                child: const _FilterChips(),
              ),
            ),
            Expanded(
              // One position in the tree either way: moving the list
              // rebuilds its Scrollable, and a fresh scroll position
              // starts at the top.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // The floors hold for what the queue and the entry get
                  // once each has taken the side inset it stands against.
                  final insets = MediaQuery.paddingOf(context);
                  final room = constraints.maxWidth - insets.horizontal;
                  final seam = _listWidth(room, seamAt);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: widget.openEntryId == null
                            ? constraints.maxWidth
                            : seam +
                                  (Directionality.of(context) ==
                                          TextDirection.rtl
                                      ? insets.right
                                      : insets.left),
                        child: WaxInsetsTaken(
                          end: widget.openEntryId != null,
                          child: SafeArea(top: false, child: _queue(sizeClass)),
                        ),
                      ),
                      if (widget.openEntryId case final open?) ...<Widget>[
                        // The seam only exists where there are two panes,
                        // which is also why there is none on a phone: below
                        // the threshold the entry takes the screen and there
                        // is nothing to divide.
                        SafeArea(
                          top: false,
                          left: false,
                          right: false,
                          child: WaxSplitter(
                            position: seam,
                            min: ReviewSurface.listMin,
                            max: _listMax(room),
                            semanticsId: SemanticsIds.reviewSplitter,
                            onChanged: (width) =>
                                setState(() => _dragging = width),
                            onSettled: (width) {
                              setState(() => _dragging = null);
                              ref
                                  .read(reviewListWidthProvider.notifier)
                                  .set(width.round());
                            },
                            onReset: () {
                              setState(() => _dragging = null);
                              ref.read(reviewListWidthProvider.notifier).set(0);
                            },
                          ),
                        ),
                        Expanded(
                          child: WaxInsetsTaken(
                            start: true,
                            child: _pane(open),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pane(String entryId) {
    return Semantics(
      identifier: SemanticsIds.reviewPane,
      container: true,
      child: ReviewEntryView(
        key: ValueKey(entryId),
        entryId: entryId,
        onClose: () => context.go(WaxRoute.review),
        onDecided: () => unawaited(_follow(entryId)),
        leaving: _leaving == entryId,
      ),
    );
  }

  Widget _queue(WaxSizeClass sizeClass) {
    final queue = ref.watch(reviewQueueProvider);
    // Rows first, whatever the load state: every decision invalidates
    // the queue, and flashing 200 rows to a skeleton would lose the
    // scroll position the pane exists to preserve.
    final rows = queue.value;
    if (rows != null) return _list(rows, sizeClass);
    return switch (queue) {
      // hasError rather than AsyncError: Riverpod retries a failed fetch
      // on its own, and a retry in flight is an AsyncLoading still
      // carrying the failure it is retrying. Matching the settled state
      // alone drops the error card to a skeleton for as long as the
      // fetch keeps failing, which is exactly when it must not.
      AsyncValue(hasError: true) => Padding(
        padding: sizeClass.gutter,
        child: AsyncFailureCard.from(
          queue,
          title: context.l10n.reviewLoadError,
          onRetry: () => ref.invalidate(reviewQueueProvider),
        ),
      ),
      _ => const SkeletonShapes(shape: SkeletonShape.list),
    };
  }

  Widget _list(ReviewQueueState state, WaxSizeClass sizeClass) {
    if (state.entries.isEmpty) {
      return Padding(
        padding: sizeClass.gutter,
        child: EmptyState(
          glyph: WaxIcons.check,
          title: context.l10n.reviewEmptyTitle,
          message: context.l10n.reviewEmptyMessage,
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.pixels >= metrics.maxScrollExtent - 400) {
          ref.read(reviewQueueProvider.notifier).loadMore();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scroll,
        itemExtent: _rowExtent,
        itemCount: state.entries.length + (state.loadingMore ? 1 : 0),
        findChildIndexCallback: indexByKey(state.entries, _reviewKey),
        itemBuilder: (context, index) {
          if (index >= state.entries.length) {
            return const SkeletonShapes(shape: SkeletonShape.list, count: 1);
          }
          final entry = state.entries[index];
          return _ReviewRow(
            key: _reviewKey(entry),
            entry: entry,
            selected: index == _selected,
            open: entry.id == widget.openEntryId,
            selecting: _selecting,
            checked: _checked.contains(entry.id),
            onTap: () => _selecting ? _toggleChecked(entry) : _open(entry),
            onLongPress: () => setState(() {
              _selecting = true;
              _checked.add(entry.id);
            }),
          );
        },
      ),
    );
  }
}

/// The bulk decision bar, along the page's foot while selecting, under
/// the queue and any pane beside it: it decides the checked rows, and the
/// pane keeps its own decision bar, standing on this one, for the entry
/// it shows.
class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.count,
    required this.busy,
    required this.busyBy,
    required this.onDecide,
  });

  final int count;

  /// Whether a decision holds the selection (none takes a press), and
  /// whether it is this bar's [action], which draws busy.
  final bool busy;
  final bool Function(String action) busyBy;
  final void Function(String action) onDecide;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    // On the page's foot: its surface runs under the insets there, its
    // contents keep clear of them.
    return ColoredBox(
      color: colors.surface2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WaxSpace.s16,
            vertical: WaxSpace.s8,
          ),
          child: Row(
            children: <Widget>[
              Text(
                context.l10n.reviewSelectedCount(count),
                style: WaxType.label.copyWith(color: colors.textSecondary),
              ),
              const Spacer(),
              WaxButton(
                label: context.l10n.reviewActionApprove,
                kind: WaxButtonKind.text,
                semanticsId: SemanticsIds.reviewBulkApprove,
                busy: busyBy('approve'),
                onPressed: busy ? null : () => onDecide('approve'),
              ),
              WaxButton(
                label: context.l10n.reviewActionAsIs,
                kind: WaxButtonKind.text,
                semanticsId: SemanticsIds.reviewBulkAsIs,
                busy: busyBy('as-is'),
                onPressed: busy ? null : () => onDecide('as-is'),
              ),
              WaxButton(
                label: context.l10n.reviewActionSkip,
                kind: WaxButtonKind.text,
                semanticsId: SemanticsIds.reviewBulkSkip,
                busy: busyBy('skip'),
                onPressed: busy ? null : () => onDecide('skip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The per-library matching mode, admin only. It stays here as well as
/// on the libraries table: this is where somebody notices a library is
/// asking too much, and another page would lose the thought.
class _MatchingModeMenu extends ConsumerWidget {
  const _MatchingModeMenu();

  static const _modes = ['auto', 'review', 'off'];

  /// The singles toggle rides the mode rows: not a mode (it composes
  /// with `auto`), so it carries its own action sentinel.
  static const _singlesAction = 'singles';

  /// The client's word for a mode, with the wire value as the last
  /// resort - the shape every other open vocabulary here keeps, so a
  /// mode a newer server invents draws as itself.
  static String _modeLabel(AppLocalizations l10n, String mode) =>
      switch (mode) {
        'auto' => l10n.reviewMatchingAuto,
        'review' => l10n.reviewMatchingReview,
        'off' => l10n.reviewMatchingOff,
        _ => mode,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin =
        ref
            .watch(authControllerProvider)
            .value
            ?.user
            ?.roles
            .contains('admin') ??
        false;
    if (!isAdmin) return const SizedBox.shrink();
    final libraries = [
      ...?ref.watch(librariesProvider).value?.where(libraryTakesMatching),
    ];
    if (libraries.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    return WaxMenuButton<(String, String)>(
      glyph: WaxIcons.filter,
      label: l10n.reviewMatchingMenu,
      semanticsId: SemanticsIds.matchingMenu,
      items: <WaxMenuItem<(String, String)>>[
        for (final library in libraries) ..._libraryRows(ref, l10n, library),
      ],
      onSelected: (choice) => choice.$2 == _singlesAction
          ? _toggleSingles(l10n, ref, choice.$1)
          : _set(l10n, ref, choice.$1, choice.$2),
    );
  }

  /// One library's rows: the three modes, then the singles toggle.
  /// Rows disable until the stored value is here - every write is a
  /// full replace, and a tap that cannot see the current state would
  /// write a guess over it.
  List<WaxMenuItem<(String, String)>> _libraryRows(
    WidgetRef ref,
    AppLocalizations l10n,
    LibraryInfo library,
  ) {
    final matching = ref.watch(libraryMatchingProvider(library.pid)).value;
    return <WaxMenuItem<(String, String)>>[
      for (final mode in _modes)
        WaxMenuItem<(String, String)>(
          value: (library.pid, mode),
          label: l10n.reviewMatchingRow(library.name, _modeLabel(l10n, mode)),
          semanticsId: SemanticsIds.matchingOption(library.pid, mode),
          selected: matching?.mode == mode,
          enabled: matching != null,
        ),
      WaxMenuItem<(String, String)>(
        value: (library.pid, _singlesAction),
        label: l10n.reviewMatchingRow(library.name, l10n.reviewMatchingSingles),
        help: l10n.reviewMatchingSinglesHelp,
        semanticsId: SemanticsIds.matchingSingles(library.pid),
        selected: matching?.singlesAutoApply ?? false,
        // A mode outside the fixed list cannot be echoed back on the
        // full-replace write, so the toggle waits for a build that
        // knows the mode.
        enabled: matching != null && _modes.contains(matching.mode),
      ),
    ];
  }

  Future<void> _set(
    AppLocalizations l10n,
    WidgetRef ref,
    String libraryPid,
    String mode,
  ) async {
    try {
      await ref
          .read(libraryMatchingProvider(libraryPid).notifier)
          .setMode(mode);
    } on WaxDeckApiException catch (e) {
      ref.read(shellMessengerProvider).show(explainError(l10n, e));
    }
  }

  Future<void> _toggleSingles(
    AppLocalizations l10n,
    WidgetRef ref,
    String libraryPid,
  ) async {
    final on =
        ref.read(libraryMatchingProvider(libraryPid)).value?.singlesAutoApply ??
        false;
    try {
      await ref
          .read(libraryMatchingProvider(libraryPid).notifier)
          .setSinglesAutoApply(!on);
    } on WaxDeckApiException catch (e) {
      ref.read(shellMessengerProvider).show(explainError(l10n, e));
    }
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  static String _label(
    AppLocalizations l10n,
    ReviewFilter filter,
    ReviewStats? stats,
  ) {
    if (stats == null) return filter.labelOf(l10n);
    final count = switch (filter) {
      ReviewFilter.pending => stats.pending,
      ReviewFilter.autoApplied => stats.autoApplied,
      ReviewFilter.decided => stats.decided,
    };
    return l10n.reviewFilterCount(filter.labelOf(l10n), count);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(reviewFilterProvider);
    final stats = ref.watch(reviewStatsProvider).value;
    return FilterChipRow(
      padding: EdgeInsets.zero,
      selected: selected.name,
      chips: <WaxFilterChip>[
        for (final filter in ReviewFilter.values)
          WaxFilterChip(
            name: filter.name,
            label: _label(context.l10n, filter, stats),
            semanticsId: SemanticsIds.reviewFilter(filter.name),
          ),
      ],
      onSelect: (name) => ref
          .read(reviewFilterProvider.notifier)
          .select(ReviewFilter.values.byName(name)),
    );
  }
}

/// A row's key, so the row moves with its entry (see [indexByKey]): an
/// entry with no title reads the same as every other one without.
Key _reviewKey(ReviewEntry entry) => ValueKey(SemanticsIds.reviewRow(entry.id));

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    super.key,
    required this.entry,
    required this.selected,
    required this.open,
    required this.selecting,
    required this.checked,
    required this.onTap,
    required this.onLongPress,
  });

  final ReviewEntry entry;

  /// Where the keyboard cursor is. Distinct from [open], which is the
  /// entry the pane holds: they are the same row almost always, and are
  /// two different facts the moment the pane is closed.
  final bool selected;
  final bool open;
  final bool selecting;
  final bool checked;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static String bestLine(AppLocalizations l10n, CandidateSummary best) {
    final percent = '${best.similarityPct.round()}';
    final year = best.year;
    return year == null
        ? l10n.reviewCandidateLine(percent, best.title, best.artist)
        : l10n.reviewCandidateLineYear(
            percent,
            best.title,
            best.artist,
            '$year',
          );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final best = entry.best;
    final name = entry.title ?? l10n.reviewUntitled;
    final title = entry.artist == null
        ? name
        : l10n.reviewEntryLine(name, entry.artist!);
    final surface = selected || open ? colors.accentContainer : colors.canvas;
    return WaxInkTappable(
      label: title,
      semanticsId: SemanticsIds.reviewRow(entry.id),
      // The tick is inside this control and reports nothing of its own,
      // so the row carries the checked state for a screen reader.
      selected: selecting ? checked : open,
      surface: surface,
      borderRadius: BorderRadius.zero,
      onPressed: onTap,
      onLongPress: onLongPress,
      color: surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WaxSpace.s16,
          vertical: WaxSpace.s8,
        ),
        child: Row(
          children: <Widget>[
            if (selecting) ...<Widget>[
              WaxIcon(
                checked ? WaxIcons.success : WaxIcons.check,
                size: 18,
                color: checked ? colors.accent : colors.textTertiary,
                active: checked,
              ),
              const SizedBox(width: WaxSpace.s12),
            ],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: WaxType.titleItem.copyWith(
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: WaxSpace.s4),
                  if (entry.identifying)
                    Row(
                      children: <Widget>[
                        const WaxSpinner(),
                        const SizedBox(width: WaxSpace.s8),
                        Text(
                          l10n.reviewIdentifying,
                          style: WaxType.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      best == null
                          ? l10n.reviewRowNoCandidates(entry.trackCount)
                          : l10n.reviewRowBest(
                              entry.trackCount,
                              bestLine(l10n, best),
                            ),
                      style: WaxType.caption.copyWith(
                        color: best == null
                            ? colors.textTertiary
                            : colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            DomainBadge(
              waxDomainOf(entry.mediaType),
              label: _originLabel(l10n, context.waxL10n, entry),
              compact: true,
            ),
            // The pane drops its warning once decided; so does the row.
            if (entry.status == 'pending' &&
                entry.duplicateCount > 0) ...<Widget>[
              const SizedBox(width: WaxSpace.s4),
              CodecChip(
                l10n.reviewDuplicateCount(entry.duplicateCount),
                emphasis: true,
              ),
            ],
            if (entry.status != 'pending') ...<Widget>[
              const SizedBox(width: WaxSpace.s4),
              CodecChip(entry.status),
            ],
          ],
        ),
      ),
    );
  }

  /// Where the unit came from, in the badge that would otherwise say
  /// the media type twice: the queue is one domain deep at a time and
  /// "Upload" is the fact a reviewer is actually sorting by.
  static String _originLabel(
    AppLocalizations l10n,
    WaxLocalizations wax,
    ReviewEntry entry,
  ) => switch (entry.origin) {
    'upload' || 'acquisition' => reviewOriginLabel(l10n, entry.origin),
    _ => DomainBadge.defaultLabel(wax, waxDomainOf(entry.mediaType)),
  };
}
