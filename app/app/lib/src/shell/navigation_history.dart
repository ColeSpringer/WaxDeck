import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'browser_history/browser_history_port.dart';
import 'routes.dart';

/// Where the visitor has been, so back returns there rather than up.
///
/// Recorded from the router's delegate, one visit per match list. A change
/// that only takes pages off the top of the visit on screen (a pop, the
/// player collapsing, an up `go`) and keeps its root's query and extra is
/// not a new visit: it steps back to the visit it lands on, or rewrites the
/// one it left. A `replace` rewrites it too. The list is bounded and keeps
/// a cursor, so the visits ahead of a step back survive until the next
/// visit is recorded.
///
/// On web the browser keeps the same list, so back walks it: a step back
/// is the browser's own, and a browser back or forward moves the cursor to
/// the visit it lands on. A visit behind or ahead is matched by the entry,
/// which keeps a visit's locations and page keys; landing on neither, the
/// list starts over there. An entry of a location forgotten is passed on
/// the way, never shown; one of a location that became another shows its
/// visit, which the list kept as that one's, until that one is forgotten
/// in turn.
///
/// The list and what [forget] was told are the session's own, held in
/// memory. After a reload each entry resolves by what the server says
/// then, so an entry of a merged or deleted record that the session had
/// not written over shows the "not here" state, as anything deleted
/// elsewhere does.
///
/// Built beside the router and found through it, so a router built
/// without one (a widget test's host) answers null and back leaves the
/// way `leave` does.
class WaxHistory {
  WaxHistory(
    this._router, {
    required this._branchRoots,
    BrowserHistoryPort? browser,
  }) : _browser = browser {
    _byRouter[_router] = this;
    _unlisten = browser?.listen(_browserMoved);
  }

  /// How many visits the list holds, the oldest dropped first.
  static const _bound = 50;

  /// How many of what [forget] was given are kept, oldest dropped first:
  /// a delete names up to three per item, and one album holds up to 500,
  /// so this keeps several such deletes at a few hundred kilobytes.
  static const _remembered = 5000;

  /// How many entries the list does not hold a browser move passes in a
  /// row: a step back's, before it goes to the visit it was after the
  /// router's way, and a visitor's own, before the router shows one.
  static const _strays = 5;

  /// How long a step asked of the browser may take to land before it is
  /// given up: a browser that dropped its oldest entries answers a step
  /// past them with nothing.
  @visibleForTesting
  static const unansweredStep = Duration(seconds: 2);

  static final _byRouter = Expando<WaxHistory>('WaxHistory');

  /// The history built with [router], or null.
  static WaxHistory? of(GoRouter router) => _byRouter[router];

  final GoRouter _router;

  /// Each branch's root location, by branch index; a branch past the end
  /// has none.
  final List<String> _branchRoots;

  final _visits = <_Visit>[];
  var _cursor = -1;

  /// The last visit recorded in each branch, by branch index, for a tab
  /// tap to bring back: without what [forget] was given since, or null
  /// where nothing of it stays, and with the pages of a location that
  /// became another moved there, none taken (see [_become]). Kept when
  /// [forget] drops the visit from the list, as go_router keeps the
  /// branch's stack.
  final _lastIn = <int, _Visit?>{};

  /// The pages taken from a branch's last visit while the branch was off
  /// screen, by branch index, bottom first, with the pushes among them.
  /// Its navigator still holds them, and go_router that navigator as it
  /// was: taken out at once they could not be shown again by a move to
  /// the same place, so they go as the branch is next shown without
  /// them, in that frame, where left to the navigator the top one would be
  /// seen leaving.
  final _waiting = <int, ({List<Object> pages, List<_Push> pushes})>{};

  /// The move this history is making, which the change it causes is read
  /// against instead of being recorded.
  _Move? _moving;

  var _tabTap = false;

  final BrowserHistoryPort? _browser;
  VoidCallback? _unlisten;

  /// Set at a browser back or forward, until the change it makes is read.
  _BrowserMove? _browserMove;

  /// The browser's position for the entry on screen as of the last change
  /// read: the entry a change by the app left (the engine records the next
  /// one after the frame, one up or in place), or the one a browser move
  /// arrived at, and where one changed nothing, the entry it reached.
  var _seen = 0;

  /// The browser step back is taking, until the entry it lands on is read.
  _ArrowBack? _arrowBack;

  /// The visit of an entry the list does not hold, which the router shows
  /// while a step back walks on past it, until the next change is read.
  _Visit? _strayShown;

  /// The pop the browser is making, until the step it takes has landed.
  _Popping? _popping;

  /// The entry the router is on, which the browser is going back to until
  /// it is there: forward again under a dialog a browser back is closing,
  /// from where a step landed that the app's own move overtook, or from
  /// the newest entry, forgotten, where a pass ran out. The engine writes
  /// to it, except where a landing this history took put the router there
  /// and what it held went as the pass began (see [_landedOn]): the engine
  /// never heard of that entry, and on the way back this is the only place
  /// it is kept.
  int? _returning;

  /// What that back closes once the browser is there again: closed first,
  /// what its closing does (a `go`, a swap) would be reported from the
  /// entry behind, and drop or overwrite the wrong one.
  Route<Object?>? _closing;

  /// How many entries a browser move of the visitor's own has passed in a
  /// row, while it is passing them: ones showing something forgotten, and
  /// copies of what is on screen. Ones that would only put the sign-in
  /// screen up again are passed without counting.
  int? _passed;

  /// The entry a landing this history took put the router on, while a pass
  /// that began from there is on its way: what the landing held went as
  /// the pass began, so the engine heard of neither, and the move the pass
  /// ends in is counted from here (see [_browserMoved]). Until that move
  /// is heard, or the pass given up.
  ///
  /// By design, not kept while the browser is being sent back to that
  /// entry, a step that cannot be called off. A move of the visitor's own
  /// heard before it lands (a third, inside the round trip of the second)
  /// is counted from the entry the engine holds the app to be on, the one
  /// the landing left, and the step then lands from wherever that move
  /// went: a page on the way can show before the browser settles, which
  /// it does with the address and the screen agreed. A go being told again
  /// on such a way back (see [_unheard]) is dropped by that move the same
  /// way, unwritten, and is undone. Telling the visitor's move from the
  /// step's own landing would take a record of every step asked of the
  /// browser and not yet landed, which this history does not keep.
  int? _landedOn;

  /// Gives up the step last asked of the browser, until a move is heard.
  Timer? _answer;

  /// Whether the engine's writes are held for a step asked of the browser,
  /// until it lands: the browser is away from the entry they are for.
  var _holding = false;

  /// Whether the router moved, not by the browser, while writes were
  /// held: that move stands, and what it wrote goes to the engine's entry.
  var _navigated = false;

  /// What a landing held, while it waits for the frame after it to be
  /// written (see [_writeHeldSoon]): past the entry a pop the app's own
  /// move overtook landed on, or over an entry of a location that became
  /// another.
  _HeldWrite? _writing;

  /// Whether the app has asked the router for a move that is not drawn
  /// yet, nor its entry written: until the frame that builds it, and in a
  /// browser until the engine has written what that frame reports.
  var _undrawn = false;

  /// Counts those moves, so the frame that draws one knows of a later one.
  var _asks = 0;

  /// Whether a step waits for that (see [_drawFirst]).
  var _drawing = false;

  /// A move the app asked of the router that no report has told the
  /// engine of yet, and whether it goes over the entry the browser is on.
  /// The router reports once a frame, what it shows then, so one the app
  /// moves on from in that frame is written as it does (see [_write]).
  ({bool inPlace})? _unwritten;

  /// The visit the app's last move added, with what a tab tap on its
  /// branch brought back before it and the visits ahead it took the place
  /// of, until the next change is read.
  _Added? _added;

  /// A move of the app's that a browser move came before the engine was
  /// told of: the browser has no entry of it and no frame drew it, so the
  /// visit it added, where it added one, goes from the list, and from its
  /// branch, as the router follows the browser. Until then, or until the
  /// browser is sent back to the entry the move was made on and the move
  /// is written after all: over that entry where it was a swap, else past
  /// it. A move of the visitor's own heard on that way back drops it
  /// unwritten instead, and a go is undone (see [_landedOn]).
  _Unheard? _unheard;

  /// How many browser moves have been heard, so a give-up that waited can
  /// tell whether one landed meanwhile.
  var _heard = 0;

  /// What [forget] was given, newest last, so a browser entry is known
  /// forgotten by its location or its top push alone.
  final _forgotten = <({String path, bool anywhere})>{};

  /// The page keys of the pushes [forget] picked out by what they were
  /// gone to with, newest last: an entry keeps a push's key, not its extra.
  final _forgottenPushes = <String>{};

  /// Where a location [forget] was told became another is now, by its
  /// path, where a browser keeps entries of it.
  final _nowAt = <String, String>{};

  /// The match list the last change arrived at.
  var _last = RouteMatchList.empty;

  /// How a step back is made once it is decided: the router's moves, or
  /// the browser's back where it keeps the list too.
  late final void Function(_BackStep step) _take = _browser == null
      ? _routerStep
      : _browserStep;

  RouteMatchList get _config => _router.routerDelegate.currentConfiguration;

  /// Whether back has somewhere recorded to return to.
  bool get canGoBack => _target(_visitOf(_config)) != null;

  /// Whether the visit on screen was made by the navigation chrome, which
  /// Android's system back climbs out of rather than undoing.
  bool get atTabTap {
    if (_cursor < 0) return false;
    final visit = _visits[_cursor];
    final here = _visitOf(_config);
    return visit.tabTap && here != null && visit.sameAs(here);
  }

  /// Whether a step back through the browser is under way, a browser
  /// move is passing entries (forgotten ones, copies of what is on screen,
  /// ones that would only put the sign-in screen up again), or the browser
  /// is going back to the entry the router is on (see [_returning]): each
  /// moves on past an entry it did not want by itself. A step the app's
  /// own move overtook is under way until it lands too, and a landing until
  /// what it held is written.
  bool get stepping =>
      _arrowBack != null ||
      _popping != null ||
      _passed != null ||
      _returning != null ||
      _holding ||
      _writing != null;

  /// The completers the visits hold for whoever awaits their pushes, with
  /// those a tab tap would bring back.
  @visibleForTesting
  List<Completer<Object?>> get heldAwaiters => [
    ...{
      for (final visit in _everyVisit)
        for (final push in visit.pushes) ?push.completer,
    },
  ];

  /// Every visit held: the list's, and each branch's last.
  Iterable<_Visit> get _everyVisit => [..._visits, ..._lastIn.values.nonNulls];

  /// Whether the visit directly behind the one on screen is [location],
  /// with nothing pushed over it.
  bool isBehind(String location) {
    final here = _visitOf(_config);
    if (here == null || _cursor < 1 || !_visits[_cursor].sameAs(here)) {
      return false;
    }
    final behind = _visits[_cursor - 1];
    return behind.pushes.isEmpty && behind.root == Uri.parse(location);
  }

  /// Completes once every step asked of the browser has landed, after the
  /// frame that builds the arrival, and once a move a step waits on is
  /// drawn (see [_drawFirst]); null with neither. A step asked meanwhile
  /// takes its turn after it, decided from where it lands.
  Future<void>? get landing => _landing?.future;
  Completer<void>? _landing;

  /// Results of pops asked while a back of the visitor's was taking their
  /// page off, by page key, for that page's opener.
  final _carried = <LocalKey, Object?>{};

  /// Waits for a step on its way before a pop of the page on top with
  /// [result], and completes with whether that pop is still to be made:
  /// not where the visitor's own back (the arrow, a browser move passing
  /// entries) took the page off meanwhile, which [result] then went to the
  /// page's opener with. A pop under way is a move of its own, so one
  /// asked after it is made from where it lands. Null with nothing on its
  /// way.
  Future<bool>? popTurn(Object? result) {
    _drawFirst();
    final landing = this.landing;
    if (landing == null) return null;
    final page = topPage;
    final visitors = _popping == null && page != null;
    if (visitors) _carried[page.key] = result;
    return landing.then((_) {
      if (!visitors) return true;
      _carried.remove(page.key);
      return topPage == page;
    });
  }

  /// Whether a route that is not a page (a dialog, a sheet, a menu) is on
  /// top of a navigator on screen. Back closes that before it moves the
  /// screen underneath.
  bool get pagelessOnTop => _pagelessTop() != null;

  /// The page on top of the screen, under whatever is open over it, told
  /// apart by where it is (see [PageId]).
  PageId? get topPage => pageOnTop(_router);

  /// Closes every dialog, sheet and menu on screen, the top one first, as
  /// a back each would; completes once none is up, or once one refuses.
  Future<void> closePageless() async {
    for (var top = _pagelessTop(); top != null; top = _pagelessTop()) {
      await _router.routerDelegate.popRoute();
      if (identical(_pagelessTop(), top)) return;
    }
  }

  /// The route that is not a page on top of the topmost navigator on
  /// screen that has one, which a back closes first.
  Route<Object?>? _pagelessTop() => _pagelessTopOf(_router);

  /// Notes the match list the router has just arrived at.
  void record() {
    _record();
    _settled();
    _releaseAfterFrame();
  }

  var _releasing = false;

  /// Lets each visit's push go of a completer it can no longer reuse, once
  /// the frame that builds the arrival has taken off the pages it left.
  void _releaseAfterFrame() {
    if (_releasing) return;
    _releasing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _releasing = false;
      for (final visit in _everyVisit) {
        for (final push in visit.pushes) {
          push.release();
        }
      }
    });
  }

  void _record() {
    final config = _config;
    final departed = _last;
    _last = config;
    final asked = config != departed && _askedSince(departed);
    final unwritten = _unwritten;
    if (asked) {
      // A swap of a move never written takes its place in the browser too.
      _unwritten = (inPlace: _replacing && (unwritten?.inPlace ?? true));
      _drawSoon();
    } else if (config != departed) {
      // The browser's move, or the router's own after a pop: nothing of
      // the app's is left to write.
      _unwritten = null;
    }
    final marked = _browserMove;
    _browserMove = null;
    final stray = _strayShown;
    _strayShown = null;
    final unheard = _unheard;
    _unheard = null;
    _added = null;
    // A move the app made while a step is on its way overtakes the step,
    // whose own landing then leaves the router where it is.
    if (_holding && marked == null) {
      _navigated = true;
      // Made over an entry the router showed on the way, which the
      // browser goes back to and writes the move past: the list holds it
      // there too, in place of the visit the step left.
      if (stray != null && _cursor >= 0) _insertAtCursor(stray);
    }
    if (_browser != null) _sample();
    final arrow = _arrowBack;
    _arrowBack = null;
    _passed = null;
    if (marked != null) _settle(departed, config);
    if (unheard?.added case final added? when marked != null) _unhear(added);
    final arriving = _visitOf(config, tabTap: _tabTap);
    final move = _moving;
    _moving = null;
    if (arriving == null) {
      // A sign-in screen, which the list never holds, gone to again.
      if (WaxRoute.authLocations.contains(config.uri.path)) {
        _unforget(<String>[config.uri.path]);
      }
      if (marked != null) _walked();
      return;
    }
    final added = (
      visit: arriving,
      known: _lastIn.containsKey(arriving.branch),
      last: _lastIn[arriving.branch],
      ahead: _visits.sublist(_cursor + 1),
    );
    if (arriving.branch case final branch?) {
      _lastIn[branch] = arriving;
      if (_waiting.containsKey(branch)) _removeWaitingSoon();
    }
    _visited(arriving);
    if (move != null) {
      _arrive(move, arriving);
      return;
    }
    if (marked != null) {
      _browserArrived(arriving, arrow, forward: marked.forward);
      _walked();
      return;
    }
    if (_cursor < 0) {
      _add(arriving);
      _added = added;
      return;
    }
    final current = _visits[_cursor];
    if (arriving.sameAs(current)) return;
    if (!arriving.tabTap && arriving.isAncestorOf(current)) {
      for (var i = _cursor - 1; i >= 0; i--) {
        final earlier = _visits[i];
        if (earlier.samePages(arriving)) {
          _visits[i] = arriving.marked(earlier.tabTap);
          _cursor = i;
          return;
        }
        if (!arriving.isAncestorPagesOf(earlier)) break;
      }
      _visits[_cursor] = arriving.marked(current.tabTap);
      return;
    }
    if (_replacing) {
      _visits[_cursor] = arriving.marked(current.tabTap);
      return;
    }
    // A visit past one the app moved to in this frame, which no report
    // wrote: written now, so the browser holds both, as the list does.
    if (asked && unwritten != null && _browser != null) {
      _write(departed, inPlace: unwritten.inPlace);
    }
    _add(arriving);
    _added = added;
  }

  /// Takes the visit of [unheard] out again: the browser was never on an
  /// entry of it, so the visits either side of where it went are those of
  /// the visit behind (the ones ahead it took the place of are put back:
  /// the browser still holds their entries), and a tab tap brings its
  /// branch back as before.
  void _unhear(_Added unheard) {
    final visit = unheard.visit;
    if (_cursor >= 0 && identical(_visits[_cursor], visit)) {
      _drop(_cursor);
      _visits.insertAll(_cursor + 1, unheard.ahead);
    }
    final branch = visit.branch;
    if (branch == null || !identical(_lastIn[branch], visit)) return;
    if (unheard.known) {
      _lastIn[branch] = unheard.last;
    } else {
      _lastIn.remove(branch);
    }
  }

  /// Takes out the visit of a move the app made in this frame, which a
  /// browser move overtook before the engine was told of it, where this
  /// history shows what that move landed on itself: the router hears of
  /// no browser move to take it out at (see [_record]).
  void _unhearOvertaken() {
    final unheard = _unheard;
    _unheard = null;
    if (unheard?.added case final added?) _unhear(added);
  }

  /// Returns to the last visit that is not on screen and still resolves:
  /// by popping when what is being undone is a push still on top, so an
  /// awaited push hears back, and by restoring the visit otherwise. With
  /// nowhere recorded it leaves as `leave` does: it pops a page with one
  /// under it, and otherwise goes up to [fallback], the branch root, home.
  void back({String? fallback}) {
    // Unless a browser back is closing it already, once it is back.
    if (_returning == null && pagelessOnTop) {
      unawaited(_router.routerDelegate.popRoute());
      return;
    }
    _drawFirst();
    // A step on its way lands first, and this one is then decided from
    // there, while the page it was asked on is still up: one that went
    // has been left.
    if (landing case final landing?) {
      final page = topPage;
      unawaited(
        landing.then((_) {
          if (topPage == page) back(fallback: fallback);
        }),
      );
      return;
    }
    final step = _stepFrom(_visitOf(_config), fallback);
    if (step == null) return;
    // A location with no screen has no browser entry: the router reports
    // nothing for it, so the browser's back would pass the visit before.
    if (_config.isError) {
      _routerStep(step);
    } else {
      _take(step);
    }
  }

  /// Pops the page on top, answering whoever awaits it with [result], and
  /// completes once the pop has landed.
  ///
  /// Where the browser keeps the list, a push is taken off by the
  /// browser's own back: the push made its entry just ahead of the one it
  /// was pushed over, and go_router reports a router pop as a new entry,
  /// which the next back would land on. A dialog, sheet or menu on top
  /// closes the ordinary way. Asked while a step is on its way, it takes
  /// its turn after it (see [popTurn]), if a page is still there to pop.
  Future<void> pop([Object? result]) {
    if (popTurn(result) case final turn?) {
      return turn.then((go) => go && _router.canPop() ? pop(result) : null);
    }
    if (_browserPop(result) case final landed?) return landed;
    _router.pop<Object?>(result);
    return SynchronousFuture<void>(null);
  }

  /// Drops every visit at or beneath [location], for a screen that has
  /// left an entity it deleted. Called after the leave: a pop is decided
  /// from the visit on screen and the one it was pushed over, which this
  /// takes out of the list.
  ///
  /// With [anywhere], [location] is a tail: a path that ends with it or
  /// holds it followed by a `/` is the entity's too, whatever it is
  /// nested under (an episode, opened on its own or beneath its show).
  /// [where] keeps only the visits whose extra it accepts, the root's or
  /// the push's own, for an entity a location carries only in memory.
  ///
  /// A browser entry of [location] is passed on the way rather than
  /// shown, until the location is visited again, or the tab reloads: what
  /// was forgotten is the session's (see [WaxHistory]). With [where],
  /// which an entry cannot answer (it keeps no extra), an entry of a push
  /// it picks out is told by the page key the entry keeps, and one of a
  /// visit's own page it picks out, or of a sign-in screen, which the list
  /// never holds, by the location alone. A tab tap brings its branch back
  /// without it (see [showBranch]), and its page, where it waits in a
  /// branch off screen, leaves that unseen as the branch is next shown.
  ///
  /// With [instead], [location] became that one (a record merged into
  /// another), and every page at or beneath it is the same page there from
  /// now on, wherever it sits: a visit's own or one pushed in it, in the
  /// list or in a branch's last visit. Each visit keeps its place with
  /// those pages moved (see [_asBecame]), and an entry of one shows that
  /// visit, written over it (see [_landOnKept]), until what it became is
  /// forgotten itself: its entries are then passed too. Nothing is dropped
  /// but a page that would lie on itself, of two visits side by side that
  /// are then one place, one, and a visit the table matches nothing for
  /// where it would be (see [_asKept]). Told by its path alone: neither
  /// [anywhere] nor [where] goes with it.
  void forget(
    String location, {
    bool anywhere = false,
    bool Function(Object? extra)? where,
    String? instead,
  }) {
    assert(
      instead == null || (!anywhere && where == null),
      'a location that became another is told by its path',
    );
    final gone = Uri.parse(location).path;
    bool under(String at, Object? extra) =>
        _holds(Uri.parse(at).path, gone, anywhere: anywhere) &&
        (where?.call(extra) ?? true);

    // Only a browser keeps entries to pass.
    if (_browser != null) {
      if (instead != null) {
        _nowAt
          ..remove(gone)
          ..[gone] = instead;
        if (_nowAt.length > _remembered) {
          _nowAt.remove(_nowAt.keys.first);
        }
      }
      var byLocation = where == null || WaxRoute.authLocations.contains(gone);
      for (final visit in _everyVisit) {
        if (under(visit.root.path, visit.extra)) byLocation = true;
        // A push that became another is that one's under the key it had.
        if (instead != null) continue;
        for (final push in visit.pushes) {
          if (under(push.location, push.extra)) {
            _remember(_forgottenPushes, push.pageKey.value);
          }
        }
      }
      if (byLocation) {
        _remember(_forgotten, (path: gone, anywhere: anywhere));
      }
    }

    if (instead != null) {
      _become(gone, instead);
      _changes.changed();
      return;
    }
    for (var i = _visits.length - 1; i >= 0; i--) {
      final visit = _visits[i];
      if (!under(visit.root.path, visit.extra) &&
          !visit.pushes.any((push) => under(push.location, push.extra))) {
        continue;
      }
      _drop(i);
    }
    // The visits either side of a forgotten one can be one place twice.
    for (var i = _visits.length - 1; i > 0; i--) {
      if (_visits[i].sameAs(_visits[i - 1])) _drop(i);
    }
    final shown = _parts(_config).branch;
    for (final MapEntry(key: branch, value: last) in _lastIn.entries.toList()) {
      if (last == null) continue;
      final kept = _lastIn[branch] = _without(last, under);
      // The branch on screen is its caller's to leave or take out of.
      if (branch == shown || identical(kept, last)) continue;
      final stays = {for (final push in kept?.pushes ?? const <_Push>[]) push};
      _leaveUnseen(
        branch,
        pages: [
          for (final page in last.pages.skip(kept?.pages.length ?? 0))
            if (page.location.isNotEmpty) page.key,
        ],
        pushes: [
          for (final push in last.pushes)
            if (!stays.contains(push)) push,
        ],
      );
    }
    _changes.changed();
  }

  /// Has every visit held show the pages at or beneath [gone] as those of
  /// [instead] (see [forget]).
  void _become(String gone, String instead) {
    String? became(String path) => _holds(path, gone, anywhere: false)
        ? instead + path.substring(gone.length)
        : null;
    // A branch's last visit is the list's own where it holds it.
    final kept = Map<_Visit, _Visit?>.identity();
    _Visit? now(_Visit visit) =>
        kept.putIfAbsent(visit, () => _asKept(visit, became));
    final moved = Set<_Visit>.identity();
    for (var i = _visits.length - 1; i >= 0; i--) {
      final visit = _visits[i];
      final to = now(visit);
      if (to == null) {
        // The table matches nothing there.
        _drop(i);
      } else if (!identical(to, visit)) {
        moved.add(_visits[i] = to);
      }
    }
    // Two side by side that are one place now are one visit: the one that
    // kept what it was gone to with stays.
    for (var i = _visits.length - 1; i > 0; i--) {
      final (behind, ahead) = (_visits[i - 1], _visits[i]);
      if (!moved.contains(behind) && !moved.contains(ahead)) continue;
      if (!ahead.isEntryOf(behind, behind.root)) continue;
      _drop(moved.contains(ahead) ? i : i - 1);
    }
    final shown = _parts(_config).branch;
    for (final MapEntry(key: branch, value: last) in _lastIn.entries.toList()) {
      if (last == null) continue;
      final to = _lastIn[branch] = now(last);
      // The branch on screen is its caller's to put in place.
      if (branch == shown || identical(to, last)) continue;
      // Its pages stay in its navigator as what they became; one cut for
      // lying on itself leaves unseen as the branch is next shown.
      final stays = {
        for (final push in to?.pushes ?? const <_Push>[]) push.pageKey,
      };
      final cut = [
        for (final push in last.pushes)
          if (!stays.contains(push.pageKey)) push,
      ];
      if (cut.isEmpty) continue;
      _leaveUnseen(
        branch,
        pages: [for (final push in cut) push.pageKey],
        pushes: cut,
      );
    }
  }

  /// [visit] once the pages [became] answers for are what they became (see
  /// [_asBecame]): the same visit there. [visit] itself where it holds
  /// none; null where the table matches nothing there.
  _Visit? _asKept(_Visit visit, String? Function(String path) became) {
    final to = _asBecame(visit.root, visit.pushes, became);
    if (to == null) return visit;
    final list = _rebuild(
      _Visit(
        root: to.root,
        // What it was gone to with was read off the record that went.
        extra: to.rootMoved ? null : visit.extra,
        pushes: to.pushes,
        branch: visit.branch,
        pages: const <_Page>[],
        tabTap: visit.tabTap,
      ),
    );
    return list == null ? null : _visitOf(list, tabTap: visit.tabTap);
  }

  /// [root] and the [pushes] over it once each page [became] answers for
  /// is what it became: at that location, its tail and its query kept, a
  /// push under the page key it had and without what it was gone to with.
  /// Where that leaves a page directly on another at the same place, one a
  /// page here became, the upper of the two is cut; with [topStays], the
  /// page on top is kept as it is and the one beneath it cut instead, and
  /// where that one is the root, both stay and [onRoot] says so. Told by
  /// the locations alone, so an entry and its visit come out the same
  /// however many records became another between them. Null where
  /// [became] answers for none.
  static ({Uri root, bool rootMoved, List<_Push> pushes, bool onRoot})?
  _asBecame(
    Uri root,
    List<_Push> pushes,
    String? Function(String path) became, {
    bool topStays = false,
  }) {
    Uri? at(Uri from) {
      final to = became(from.path);
      if (to == null) return null;
      final uri = Uri.parse(to);
      return from.hasQuery ? uri.replace(query: from.query) : uri;
    }

    final places = <String>{};
    final rootNow = at(root);
    if (rootNow != null) places.add(rootNow.toString());
    final now = <_Push>[];
    for (final push in pushes) {
      final to = at(Uri.parse(push.location));
      if (to == null) {
        now.add(push);
        continue;
      }
      places.add(to.toString());
      now.add(
        _Push(
          location: to.toString(),
          extra: null,
          pageKey: push.pageKey,
          navigator: push.navigator,
          completer: push.completer,
        ),
      );
    }
    if (places.isEmpty) return null;
    final base = (rootNow ?? root).toString();
    final kept = <_Push>[];
    var onRoot = false;
    for (final (i, push) in now.indexed) {
      bool lies() =>
          places.contains(push.location) &&
          push.location == (kept.lastOrNull?.location ?? base);
      if (topStays && i == now.length - 1) {
        while (kept.isNotEmpty && lies()) {
          kept.removeLast();
        }
        onRoot = lies();
      } else if (lies()) {
        continue;
      }
      kept.add(push);
    }
    return (
      root: rootNow ?? root,
      rootMoved: rootNow != null,
      pushes: kept,
      onRoot: onRoot,
    );
  }

  /// Adds [it] to [kept] as its newest, the oldest dropped past
  /// [_remembered].
  static void _remember<T>(Set<T> kept, T it) {
    kept
      ..remove(it)
      ..add(it);
    if (kept.length > _remembered) kept.remove(kept.first);
  }

  /// Has [pages], taken from [branch]'s last visit while the branch is
  /// off screen, leave its navigator unseen as it is next shown without
  /// them, and whoever awaits one of [pushes] among them answered then.
  void _leaveUnseen(
    int branch, {
    required List<Object> pages,
    required List<_Push> pushes,
  }) {
    final waiting = _waiting[branch];
    // Taken from under the ones before: beneath them, bottom first.
    _waiting[branch] = (
      pages: [...pages, ...?waiting?.pages],
      pushes: [...pushes, ...?waiting?.pushes],
    );
  }

  var _removing = false;

  /// Takes what waits to leave the branch on screen out of it before the
  /// frame that builds the arrival, and out of the delegate's
  /// notification: a navigator's own pop can be what notified, and it
  /// takes no other change while it makes one.
  void _removeWaitingSoon() {
    if (_removing) return;
    _removing = true;
    scheduleMicrotask(() {
      _removing = false;
      final here = _visitOf(_config);
      if (here?.branch case final branch?) _removeWaiting(branch, here!);
    });
  }

  /// Takes the pages waiting to leave [branch] unseen (see [_waiting])
  /// out of its navigator, now [arriving] is about to show it without
  /// them. One that is all its navigator holds stays: nothing is under
  /// it to show it leaving. One [arriving] shows is not taken: a push,
  /// brought back by its own entry (a step back on its way past it), goes
  /// on waiting; a declared page's key is whatever its route shows now.
  void _removeWaiting(int branch, _Visit arriving) {
    final waiting = _waiting.remove(branch);
    if (waiting == null) return;
    final shown = {for (final page in arriving.pages) page.key};
    final pushed = {for (final push in waiting.pushes) push.pageKey};
    final gone = <Object>{};
    final still = <Object>{};
    for (final key in waiting.pages.reversed) {
      if (shown.contains(key)) {
        if (pushed.contains(key)) still.add(key);
        continue;
      }
      final route = PageRoutes.of(key);
      if (route == null) {
        gone.add(key);
      } else if (!route.isFirst) {
        route.navigator?.removeRoute(route);
        gone.add(key);
      }
    }
    for (final push in waiting.pushes) {
      if (!gone.contains(push.pageKey)) continue;
      if (push.completer case final completer? when !completer.isCompleted) {
        completer.complete(_carried.remove(push.pageKey));
      }
    }
    if (still.isEmpty) return;
    _waiting[branch] = (
      pages: [
        for (final key in waiting.pages)
          if (still.contains(key)) key,
      ],
      pushes: [
        for (final push in waiting.pushes)
          if (still.contains(push.pageKey)) push,
      ],
    );
  }

  /// Takes the pages [gone] picks out, by where each is and what it was
  /// gone to with, from under the page on top, which stays as it is: what
  /// was opened over one of them is then over what lay under it, as a pop
  /// of it would show. A visit's own page with nothing declared beneath it
  /// (gone to by its link) gives way to its branch's root. Nothing where
  /// the page on top is one of them, or none is on screen. For a deleted
  /// thing's pages, still waiting under what the visitor opened over them
  /// (the full player, a push).
  ///
  /// One [instead] answers for became that location (see [forget]) and is
  /// not taken out: it is put there in place, the visit's own page and a
  /// pushed one alike (see [_asBecame]). Only a page that would then lie
  /// directly on itself goes, and where that is the visit's own, under the
  /// page on top, what is declared beneath it stands in.
  ///
  /// Made in place, it never overtakes a step on its way: it waits for
  /// that to land, and is decided from there.
  void takeOutFromUnder(
    bool Function(String location, Object? extra) gone, {
    String? Function(String location)? instead,
  }) {
    if (landing case final landing?) {
      unawaited(landing.then((_) => takeOutFromUnder(gone, instead: instead)));
      return;
    }
    _takeOut((location, extra, _) => gone(location, extra), instead: instead);
  }

  /// [takeOutFromUnder], with each page told apart by its key too; false
  /// where nothing was taken out.
  bool _takeOut(
    bool Function(String location, Object? extra, Object key) gone, {
    String? Function(String location)? instead,
  }) {
    final here = _visitOf(_config);
    if (here == null) return false;
    final pages = [
      for (final page in here.pages)
        if (page.location.isNotEmpty) page,
    ];
    String? declared;
    Uri? root;
    // Whether the visit's own page became another.
    var own = false;
    final kept = <_Push>[];
    final cut = <_Push>[];
    final out = <Object>[];
    var pushed = 0;
    for (final (at, page) in pages.indexed) {
      final top = at == pages.length - 1;
      if (page.pushed) {
        final push = here.pushes[pushed++];
        if (!gone(push.location, push.extra, push.pageKey)) {
          kept.add(push);
        } else if (top) {
          return false;
        } else if (instead?.call(Uri.parse(push.location).path) != null) {
          // Put where it became, below.
          kept.add(push);
        } else {
          out.add(push.pageKey);
          cut.add(push);
        }
        continue;
      }
      // A page declared beneath one that goes is that one's too.
      if (root != null) {
        if (top) return false;
        out.add(page.key);
        continue;
      }
      if (gone(page.location, here.extra, page.key)) {
        if (top) return false;
        if (instead?.call(page.location) != null) {
          // Put where it became, below.
          own = true;
          root = here.root;
        } else {
          final branch = here.branch;
          final under =
              declared ??
              (branch == null ? null : _branchRoots.elementAtOrNull(branch)) ??
              WaxRoute.home;
          if (under == page.location) return false;
          root = Uri.parse(under);
        }
        out.add(page.key);
        continue;
      }
      declared = page.location;
    }
    final became = instead == null
        ? null
        : _asBecame(here.root, kept, instead, topStays: true);
    if (became != null) {
      if (became.rootMoved) root = became.root;
      final stays = {for (final push in became.pushes) push.pageKey};
      for (final push in kept) {
        if (stays.contains(push.pageKey)) continue;
        out.add(push.pageKey);
        cut.add(push);
      }
      kept
        ..clear()
        ..addAll(became.pushes);
      if (own && became.onRoot) {
        final branch = here.branch;
        root = Uri.parse(
          declared ??
              (branch == null ? null : _branchRoots.elementAtOrNull(branch)) ??
              WaxRoute.home,
        );
      }
    } else if (own) {
      return false;
    }
    if (out.isEmpty && became == null) return false;
    final list = _rebuild(
      _Visit(
        root: root ?? here.root,
        extra: root == null ? here.extra : null,
        pushes: kept,
        branch: here.branch,
        pages: const <_Page>[],
        tabTap: here.tabTap,
      ),
    );
    if (list == null) return false;
    // Moved to another branch (Home standing in), what was kept over it in
    // the branch left is built in the new one, so its route there goes, and
    // nothing of that branch's last visit stays to be brought back.
    final left = _parts(list).branch == here.branch
        ? const <GlobalKey<NavigatorState>>{}
        : _branchNavigators(_config.matches);
    // What is open over them there (a sheet, a dialog, a menu) cannot come
    // along: closed first, its opener answered.
    for (final key in left) {
      final navigator = key.currentState;
      for (
        var top = _topRoute(navigator);
        top != null && top.settings is! Page<Object?>;
        top = _topRoute(navigator)
      ) {
        navigator!.removeRoute(top);
      }
    }
    for (final push in kept.reversed) {
      if (!left.contains(push.navigator)) continue;
      if (PageRoutes.of(push.pageKey) case final route?) {
        route.navigator?.removeRoute(route);
      }
    }
    // Each leaves at once, never seen leaving: under something opaque its
    // exit would wait to play once that went. One that is all its
    // navigator holds goes too where what stands in for it is built there
    // in the next frame, and stays where the move leaves its branch, or
    // where the page standing in keeps its key (its route is kept).
    final building = {for (final page in _parts(list).pages) page.key};
    for (final key in out.reversed) {
      if (PageRoutes.of(key) case final route?) {
        final lone = route.isFirst && route.isCurrent;
        if (lone && (left.isNotEmpty || building.contains(key))) continue;
        route.navigator?.removeRoute(route);
      }
    }
    // In place, on the visit and the entry on screen.
    _inPlace(
      () => _make(const _Climb(outward: false), () => _router.restore(list)),
    );
    if (left.isNotEmpty && here.branch != null) _lastIn[here.branch!] = null;
    // A push taken out answers whoever awaits it, at once: it went with
    // its route, whatever a navigator since left offstage still lists.
    for (final push in cut) {
      if (push.completer case final completer? when !completer.isCompleted) {
        completer.complete(
          push.pageKey == _popping?.pageKey
              ? _popping!.result
              : _carried.remove(push.pageKey),
        );
      }
    }
    return true;
  }

  /// The navigators of the branch [matches] show, and of the shells
  /// within it.
  static Set<GlobalKey<NavigatorState>> _branchNavigators(
    List<RouteMatchBase> matches,
  ) {
    Iterable<GlobalKey<NavigatorState>> within(
      List<RouteMatchBase> matches,
    ) sync* {
      for (final match in matches.whereType<ShellRouteMatch>()) {
        yield match.navigatorKey;
        yield* within(match.matches);
      }
    }

    for (final match in matches.whereType<ShellRouteMatch>()) {
      if (match.route is StatefulShellRoute) {
        return {match.navigatorKey, ...within(match.matches)};
      }
      final found = _branchNavigators(match.matches);
      if (found.isNotEmpty) return found;
    }
    return const {};
  }

  /// Forgets everything, for a session that is no longer the one that
  /// went there.
  void clear() {
    _visits.clear();
    _cursor = -1;
    _lastIn.clear();
    _waiting.clear();
    _changes.changed();
  }

  /// Shows [branch] for a tab tap, as the last visit recorded there,
  /// rebuilt as a step back rebuilds a visit, without what lay beside the
  /// shell (an overlay, which go_router leaves out of a branch too): where
  /// [forget] took a page of it since, up to that page, and the branch's
  /// root where nothing of it stays. False, having done nothing, where no
  /// visit was recorded there, for go_router's own restore.
  bool showBranch(int branch) {
    if (!_lastIn.containsKey(branch)) return false;
    if (_lastIn[branch] case final last?) {
      if (_rebuild(last) case final list?) {
        _router.restore(
          RouteMatchList(
            matches: _inShell(list.matches),
            uri: list.uri,
            extra: list.extra,
            error: list.error,
            pathParameters: list.pathParameters,
          ),
        );
        return true;
      }
    }
    final root = _branchRoots.elementAtOrNull(branch);
    if (root == null) return false;
    _router.go(root);
    return true;
  }

  /// [matches] without what lies beside the stateful shell, which a
  /// branch's stack leaves out.
  static List<RouteMatchBase> _inShell(List<RouteMatchBase> matches) {
    final kept = <RouteMatchBase>[];
    for (final match in matches) {
      if (match is ShellRouteMatch) {
        if (match.route is StatefulShellRoute) {
          kept.add(match);
          break;
        }
        kept.add(
          ShellRouteMatch(
            route: match.route,
            matches: _inShell(match.matches),
            matchedLocation: match.matchedLocation,
            pageKey: match.pageKey,
            navigatorKey: match.navigatorKey,
          ),
        );
        continue;
      }
      kept.add(match);
    }
    return kept;
  }

  /// [visit] up to the first of its pages [gone] picks out, as a pop of
  /// that page would leave it: a page of its own takes every page after it
  /// too, a push the pushes after it. Null where no page of its own stays;
  /// [visit] itself where nothing went.
  static _Visit? _without(
    _Visit visit,
    bool Function(String at, Object? extra) gone,
  ) {
    String? declared;
    var pushed = 0;
    for (final (at, page) in visit.pages.indexed) {
      // A shell's navigator.
      if (page.location.isEmpty) continue;
      if (page.pushed) {
        final push = visit.pushes[pushed];
        if (gone(push.location, push.extra)) {
          return _Visit(
            root: visit.root,
            extra: visit.extra,
            pushes: visit.pushes.sublist(0, pushed),
            branch: visit.branch,
            pages: visit.pages.sublist(0, at),
            tabTap: visit.tabTap,
          );
        }
        pushed++;
        continue;
      }
      if (gone(page.location, visit.extra)) {
        if (declared == null) return null;
        return _Visit(
          root: Uri.parse(declared),
          extra: null,
          pushes: const <_Push>[],
          branch: visit.branch,
          pages: visit.pages.sublist(0, at),
          tabTap: visit.tabTap,
        );
      }
      declared = page.location;
    }
    return visit;
  }

  /// Fires when the list changes with nothing navigating: visits forgotten
  /// or cleared, or a step back the router answered with no change. An
  /// arrival is the router's to report.
  Listenable get changes => _changes;
  final _changes = _Changes();

  /// Runs [navigate], a choice made on the navigation chrome, and marks
  /// the visit it makes as one.
  void tabTap(VoidCallback navigate) {
    _tabTap = true;
    try {
      navigate();
    } finally {
      _tabTap = false;
    }
  }

  /// Runs [navigate], a step out that back makes when there is nowhere
  /// recorded to return to. It rewrites the visit on screen rather than
  /// adding one, so no later back returns to where it climbed from;
  /// [outward] marks the result as the chrome's, as Android's step home is.
  void climb(VoidCallback navigate, {bool outward = false}) =>
      _make(_Climb(outward: outward), navigate);

  void dispose() {
    _answer?.cancel();
    // A landing's frame, still to come, has nothing left to write.
    _writing = null;
    _browser?.drop();
    _unlisten?.call();
    _byRouter[_router] = null;
    _changes.dispose();
  }

  /// What back does from [here], or null when it has nowhere to go.
  _BackStep? _stepFrom(_Visit? here, String? fallback) {
    final index = _target(here);
    if (index != null) {
      final to = _visits[index];
      if (here != null && to.isUnderOnePush(here) && _router.canPop()) {
        return _PopTo(index);
      }
      return _RestoreTo(index, _rebuild(to)!);
    }
    // Nowhere recorded to step to, back leaves as `leave` does: a page
    // with one under it pops, so a caller awaiting a push hears back and a
    // cold link goes up through the pages its location declares.
    if (_router.canPop()) return const _PopUp();
    final at = _config.uri.toString();
    // A sign-in screen goes up only where its own arrow says: home is
    // answered with a bare sign-in, which drops where the visitor was
    // headed.
    if (WaxRoute.authLocations.contains(_config.uri.path)) {
      return fallback == null || fallback == at ? null : _GoUp(fallback);
    }
    final branch = here?.branch;
    final root = branch == null ? null : _branchRoots.elementAtOrNull(branch);
    for (final to in <String?>[fallback, root, WaxRoute.home]) {
      if (to != null && to != at) return _GoUp(to);
    }
    return null;
  }

  void _routerStep(_BackStep step) {
    switch (step) {
      case _PopTo(:final index):
        // With what a pop asked while this step was on its way carried.
        final carried = _carried.remove(topPage?.key);
        _make(_StepTo(index), () => _router.pop<Object?>(carried));
      case _RestoreTo(:final index, :final list):
        _make(_StepTo(index), () => _router.restore(list), settle: true);
      case _PopUp():
        climb(() => _router.pop<Object?>());
      case _GoUp(:final location):
        climb(() => _router.go(location));
    }
  }

  /// A step back where the browser keeps the list: its own back, so no
  /// entry is minted ahead. The router's way where nothing is recorded or
  /// no entry of this app lies behind.
  void _browserStep(_BackStep step) {
    final browser = _browser!;
    switch (step) {
      case _PopTo(:final index) || _RestoreTo(:final index)
          when browser.canStepBack:
        _arrowBack = _ArrowBack(index, strays: _strays, from: browser.position);
        _ask(-1);
      case _PopUp():
        if (_browserPop(null) == null) _routerStep(step);
      case _:
        _routerStep(step);
    }
  }

  /// Takes the push on top off by the browser's back, with [result] for
  /// its opener; null, having done nothing, where that is not how it
  /// pops. Where the history holds the visit on screen, the one behind it
  /// has to be what the push was made over: a tab tap that brought the
  /// push back made an entry of its own over the other tab's. Where it
  /// holds none (an auth screen, a list started over on the page), the
  /// entry behind is trusted to be the base, as the push made it.
  Future<void>? _browserPop(Object? result) {
    final browser = _browser;
    if (browser == null || !browser.canStepBack || pagelessOnTop) return null;
    final (:pushes, :pages, branch: _) = _parts(_config);
    if (pages.lastOrNull?.pushed != true) return null;
    final here = _visitOf(_config);
    _ArrowBack? arrow;
    if (here != null && _cursor > 0 && _visits[_cursor].sameAs(here)) {
      if (!_visits[_cursor - 1].isUnderOnePush(here)) return null;
      arrow = _ArrowBack(_cursor - 1, strays: _strays, from: browser.position);
    }
    final popping = _popping = _Popping(
      pushes.last,
      result,
      from: browser.position,
    );
    _arrowBack = arrow;
    _ask(-1);
    return popping.landed.future;
  }

  /// Ends a browser pop once the steps it took have landed, after the
  /// frame that builds the arrival: until then the navigators still hold
  /// the page it took off, and a pop or a step read from them would take
  /// that again. Its opener is answered here if no landing did: one that
  /// still held the push answered the entry's copy of it instead.
  void _walked() {
    final popping = _popping;
    if (_arrowBack != null || popping == null) return;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (identical(_popping, popping)) _popping = null;
        final push = popping.push;
        if (push.completer case final completer?
            when !completer.isCompleted && !push.mounted) {
          completer.complete(popping.result);
        }
        if (!popping.landed.isCompleted) popping.landed.complete();
        _settled(framed: true);
      })
      ..scheduleFrame();
  }

  /// Completes [landing] once nothing asked of the browser is on its way,
  /// after the frame that builds where it landed; at once where [framed]
  /// says that frame has been.
  void _settled({bool framed = false}) {
    final landing = _landing;
    if (landing == null || stepping || _drawing) return;
    void complete() {
      if (!identical(_landing, landing) || stepping || _drawing) return;
      _landing = null;
      landing.complete();
    }

    if (framed) {
      complete();
      return;
    }
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => complete())
      ..scheduleFrame();
  }

  /// Whether the change from [departed] is a move the app asked of the
  /// router. Not the restore go_router asks for after a pop of its own,
  /// to keep the provider in step: that asks for what the pop left, and
  /// the navigators made the pop themselves.
  bool _askedSince(RouteMatchList departed) {
    final state = _router.routeInformationProvider.value.state;
    return state is RouteInformationState &&
        (state.type != NavigatingType.restore ||
            state.baseRouteMatchList != departed);
  }

  /// Notes a move the app asked of the router as not drawn until the
  /// frame that builds it has been, and in a browser until the engine has
  /// written what that frame reports: it takes what it is told in turn,
  /// some microtasks later, and answers a message sent after the report
  /// once the report's entry is written.
  void _drawSoon() {
    _undrawn = true;
    final ask = ++_asks;
    // Once the router has heard the move too, so after its report.
    scheduleMicrotask(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _unwritten = null;
        if (_browser == null) {
          _drawn(ask);
        } else {
          unawaited(
            SystemNavigator.selectMultiEntryHistory().then(
              (_) => _drawn(ask),
              onError: (Object _) => _drawn(ask),
            ),
          );
        }
      });
    });
  }

  void _drawn(int ask) {
    // A move asked since is drawn by a later frame.
    if (ask != _asks) return;
    _undrawn = false;
    if (!_drawing) return;
    _drawing = false;
    _settled(framed: true);
  }

  /// Has a step asked before the app's last move is drawn take its turn
  /// once it is, through [landing]: until then the navigators hold the
  /// pages the move left, which a pop is read off, and the browser is on
  /// the entry it left, which a step is counted from.
  void _drawFirst() {
    if (_drawing || !_undrawn) return;
    _drawing = true;
    _landing ??= Completer<void>();
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _browserMoved() {
    _heard++;
    _answer?.cancel();
    _answer = null;
    // What was on its way has landed, or this move came instead; what it
    // held is decided here.
    _holding = false;
    final writing = _writing;
    _writing = null;
    final browser = _browser!;
    final at = browser.position;
    // A landing this history took left the router on an entry the engine
    // heard nothing of, while its write is held or a pass that began there
    // is on its way: counted from there.
    final landed = writing?.over ?? _landedOn;
    _landedOn = null;
    final shown = landed ?? browser.shown;
    final (returning, closing) = (_returning, _closing);
    _returning = null;
    _closing = null;
    if (returning == at || (_navigated && at == shown)) {
      // On the entry the engine writes to, where what it wrote while the
      // browser was away goes, in order. A move it had not been told of
      // was told as the browser was sent back, and stands with the rest.
      browser.release();
      _navigated = false;
      _unheard = null;
      _sample();
      _returned(closing);
      return true;
    }
    // The app moved the router while a pop the browser makes was on its
    // way: as natively, where the pop lands first, it lands here and the
    // move goes past it.
    if (_navigated && returning == null && at < shown) {
      if (_popping case final popping?) return _poppedUnder(popping);
    }
    // The app moved the router while a step was on its way: that move
    // stands, the step is done with, and the browser goes back to the
    // entry the engine writes to before what the move wrote goes there:
    // as many entries as it is away, however many moves took it there.
    if (_navigated && returning == null) {
      _returning = shown;
      _ask(shown - at);
      return true;
    }
    // A browser back closes a dialog, a sheet or a menu first, as every
    // other back does: the router never hears of it, the browser goes
    // forward again to the entry the page beneath is on, and the dialog
    // closes once it is there. Until then the browser is one behind the
    // entry the engine writes to, which never heard of the back.
    if (at < shown && !stepping && pagelessOnTop) {
      _returning = shown;
      _closing = _pagelessTop();
      _ask(shown - at);
      return true;
    }
    // Elsewhere instead, or a step's own landing: the router follows the
    // browser there, so what was held for the entry it left goes, and a
    // move of the app's the engine was never told of with it.
    browser.drop();
    _navigated = false;
    // A move noted as unheard that a pass has reported since: what was
    // held of it went above, so the engine is still to be told.
    final untold = _unreported ? null : _unheard;
    // Not after an ask that changed nothing: no move was recorded, and the
    // visit on screen has its entry.
    if (_unreported && _undrawn) {
      _unheard = (added: _added, inPlace: _unwritten?.inPlace ?? _replacing);
    }
    if (_passOver(at, shown)) {
      // A pass from the entry that landing put the router on goes on
      // counting from it.
      if (_passed != null) _landedOn = landed;
      // Sent back to the entry the router is on, where what the engine was
      // to be told of it went above: told again, held until the browser is
      // there. What a landing showed goes over its entry, a move of the
      // app's past the one it was made on, or over it where it was a swap.
      if (_returning != null) {
        if (_returning == landed) {
          _report(inPlace: true);
        } else if (untold != null) {
          _write(_config, inPlace: untold.inPlace);
        }
      }
      return true;
    }
    _mark(at);
    return false;
  }

  /// Ends a browser pop the app's own move overtook, at the entry the
  /// pop landed on, as natively: the page it closed goes, from under the
  /// move or from the visits and its branch, its opener hears [popping]'s
  /// result, and what the move wrote goes past this entry, which drops the
  /// closed page's own. An entry of something forgotten on the way is
  /// passed first, as the pop passes it; not one of a location that became
  /// another, whose visit the list kept (see [_keptAt]).
  bool _poppedUnder(_Popping popping) {
    final browser = _browser!;
    if (_isForgotten(browser) &&
        _keptAt(browser) == null &&
        popping.strays > 0 &&
        browser.canStepBack) {
      popping.strays--;
      _ask(-1);
      return true;
    }
    _navigated = false;
    _sample();
    _closed(popping);
    // The move itself, where no frame has reported it yet: left to the
    // frame it would be written after what was held has gone, and a swap
    // then over this entry.
    _reportPending();
    // What the move wrote, with the closed page's removal, goes once the
    // engine has it all. A move the app makes before then is one more,
    // written after it.
    _writeHeldSoon(past: true);
    _walked();
    return true;
  }

  /// Has what is held at a landing written once the frame after it has
  /// been, when the engine has it all: [past] the entry the browser is on,
  /// or as it was told, over that entry. Until then the landing is under
  /// way (see [stepping]). A browser move heard first decides what is held
  /// instead (see [_browserMoved]): elsewhere, it is dropped, so nothing is
  /// written to an entry it was not made for, and where the write was to
  /// go over the entry landed on, that move is counted from this entry,
  /// which the engine never heard of, and so is the pass it may begin (see
  /// [_landedOn]).
  void _writeHeldSoon({required bool past}) {
    final browser = _browser!;
    final mine = _writing = _HeldWrite(over: past ? null : browser.position);
    _landing ??= Completer<void>();
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!identical(_writing, mine)) return;
        _writing = null;
        if (browser.release(past: past)) _sample();
        _settled(framed: true);
      })
      ..scheduleFrame();
  }

  /// Takes [popping]'s page out wherever the app's move left it, as its
  /// pop landing first would have: from the visits, a branch's last visit,
  /// and the screen, the pages over it kept. Its opener hears the result.
  void _closed(_Popping popping) {
    final gone = popping.push;
    bool isGone(_Push push) => push == gone;
    _Visit without(_Visit visit) => _Visit(
      root: visit.root,
      extra: visit.extra,
      pushes: [
        for (final push in visit.pushes)
          if (!isGone(push)) push,
      ],
      branch: visit.branch,
      pages: [
        for (final page in visit.pages)
          if (!page.pushed ||
              page.key != gone.pageKey ||
              page.location != gone.location)
            page,
      ],
      tabTap: visit.tabTap,
    );
    for (var i = 0; i < _visits.length; i++) {
      if (_visits[i].pushes.any(isGone)) _visits[i] = without(_visits[i]);
    }
    for (var i = _visits.length - 1; i > 0; i--) {
      if (_visits[i].sameAs(_visits[i - 1])) _drop(i);
    }
    final shown = _parts(_config).branch;
    for (final MapEntry(key: branch, value: last) in _lastIn.entries.toList()) {
      if (last != null && last.pushes.any(isGone)) {
        _lastIn[branch] = without(last);
        // Left in a branch the move went from, it is not seen leaving
        // when that is next shown.
        if (branch != shown) {
          _leaveUnseen(branch, pages: [gone.pageKey], pushes: [gone]);
        }
      }
    }
    // Taken out, it is answered as a push taken out is, with what the pop
    // carries.
    if (!identical(_popping, popping)) _carried[gone.pageKey] = popping.result;
    final out =
        _parts(_config).pushes.any(isGone) &&
        _takeOut(
          (location, extra, key) =>
              key == gone.pageKey && location == gone.location,
        );
    if (!out) {
      _carried.remove(gone.pageKey);
      if (gone.completer case final completer? when !completer.isCompleted) {
        completer.complete(popping.result);
      }
    }
    _changes.changed();
  }

  /// Closes [closing] now the browser is back on the entry of the page
  /// under it, where it is still on top, and ends a pop the app's own move
  /// overtook.
  void _returned(Route<Object?>? closing) {
    if (closing != null && identical(_pagelessTop(), closing)) {
      unawaited(_router.routerDelegate.popRoute());
    }
    _walked();
    _settled();
  }

  /// Marks the browser move to the entry at [at], which the router is
  /// about to hear of.
  void _mark(int at) {
    // The entry on screen is the one seen at the last change read, or the
    // one the engine pushed just above it, so a move above that is forward
    // and any other is back.
    final move = _browserMove = _BrowserMove(forward: at > _seen);
    // The router answers a move to an entry the same as the one on screen
    // with no change: a step back landing there steps on.
    Timer.run(() {
      if (!identical(_browserMove, move)) return;
      _browserMove = null;
      _unheard = null;
      _sample();
      final arrow = _arrowBack;
      _arrowBack = null;
      if (arrow != null) _stepPast(arrow);
      _walked();
      _settled();
    });
  }

  /// Asks the browser to step [by] entries, back where negative, to be
  /// given up if nothing has landed after [unansweredStep]. Until it lands
  /// the browser is away from the entry the engine writes to, so what the
  /// engine writes meanwhile is held (see [_browserMoved]), a move it was
  /// not told of yet with it.
  void _ask(int by) {
    _reportPending();
    _answer?.cancel();
    _answer = Timer(unansweredStep, _giveUp);
    _landing ??= Completer<void>();
    final browser = _browser!..hold();
    _holding = true;
    if (by == -1) {
      browser.back();
    } else {
      browser.forward(by);
    }
  }

  /// Makes the move a step that never landed was making the router's way:
  /// a pop with its result, a step back to the visit it was after, and a
  /// pass, or the step forward again under a dialog a browser back closed,
  /// by showing the entry the browser is on. Where the app moved the
  /// router meanwhile, what that wrote is written past the entry the
  /// browser is on instead, and stands. Whatever lands later is an
  /// ordinary browser move. A dialog, sheet or menu opened during the wait
  /// closes first, as back closes it, so the move is made on the page and
  /// a pop's caller goes on only once that page has gone; one that stays
  /// open is waited out again.
  void _giveUp() {
    _answer = null;
    if (pagelessOnTop) {
      final heard = _heard;
      unawaited(
        closePageless().then((_) {
          // A landing heard meanwhile was the step's own.
          if (_heard != heard || !stepping || _answer != null) return;
          if (pagelessOnTop) {
            _answer = Timer(unansweredStep, _giveUp);
          } else {
            _giveUp();
          }
        }),
      );
      return;
    }
    final browser = _browser!;
    final (popping, arrow) = (_popping, _arrowBack);
    // A pass, or a dialog's close waiting for the browser to go forward
    // again: the visitor's own move stands.
    final handOn = _passed != null || _returning != null;
    final navigated = _navigated;
    _popping = null;
    _arrowBack = null;
    _passed = null;
    _landedOn = null;
    _returning = null;
    _closing = null;
    _holding = false;
    _navigated = false;
    _strayShown = null;
    // The router's move rewrites the entry the browser is on (see
    // [_inPlace]); where that is the step's own departure, unmoved, its
    // visit has no entry left and goes too.
    final here = _visitOf(_config);
    final departure =
        (popping?.from ?? arrow?.from) == browser.position &&
            here != null &&
            _cursor >= 0 &&
            _visits[_cursor].sameAs(here)
        ? _visits[_cursor]
        : null;
    // What the app's own move wrote while the browser was away stands,
    // past the entry the browser is on, or as written where the browser
    // never left the engine's entry. Anything else held was written for an
    // entry the router has left. A pop it overtook that never left its
    // page's entry: that entry shows the page closed, so the move is
    // written over it.
    final overPop = popping != null && popping.from == browser.position;
    final past = !overPop && browser.position != browser.shown;
    var released = navigated && browser.release(past: past, over: overPop);
    if (released) {
      _sample();
    } else {
      browser.drop();
      // A move no frame has reported yet stands the same way: told now, it
      // is written where what was held would have been.
      if (navigated && _unreported) {
        _report(inPlace: overPop || (!past && _replacing));
        released = !_unreported;
      }
    }
    if (popping != null) {
      if (navigated) {
        // The move stands, over the page beneath, as natively.
        _closed(popping);
      } else if (_parts(_config).pushes.lastOrNull?.pageKey ==
              popping.pageKey &&
          !pagelessOnTop) {
        _inPlace(() => _router.pop<Object?>(popping.result));
      }
      final push = popping.push;
      if (push.completer case final completer?
          when !completer.isCompleted && !push.mounted) {
        completer.complete(popping.result);
      }
      if (!popping.landed.isCompleted) popping.landed.complete();
    } else if (arrow != null) {
      final after = math.min(arrow.index, _visits.length - 1);
      if (after >= 0) {
        final to = _visits[after];
        final departed = _config;
        if (here != null && to.isUnderOnePush(here) && _router.canPop()) {
          _inPlace(() => _routerStep(_PopTo(after)));
        } else if (_rebuild(to) case final list?) {
          _inPlace(() => _routerStep(_RestoreTo(after, list)));
        }
        // As a landing does, for a push the move took off.
        _settle(departed, _config);
      }
    } else if (handOn && !released) {
      _mark(browser.position);
      if (browser.handOn()) {
        // What a redirect answers it with is written over it.
        _neglectAnswer();
      } else {
        _browserMove = null;
      }
    }
    final left = departure == null
        ? -1
        : _visits.indexWhere((visit) => identical(visit, departure));
    if (left >= 0 && left != _cursor) _drop(left);
    _settled();
  }

  /// Runs [move], a router move the browser keeps on the entry it is on
  /// (one made where a step asked of it never came, a page taken out in
  /// place) rather than adding one past it, which would drop every entry
  /// ahead and leave the visits ahead with none: reported at once, as a
  /// replacement. Left to the frame's report under `Router.neglect`, every
  /// move made before that report would be one too, the app's own included.
  /// A move of the app's no frame has reported yet is reported first, as
  /// an entry of its own; not one [move] is [overtaking], which the browser
  /// left the entry of before the engine was told: [move] takes its place
  /// in the router, and it is never written.
  void _inPlace(VoidCallback move, {bool overtaking = false}) {
    if (!overtaking) _reportPending();
    move();
    _report(inPlace: true);
  }

  /// Reports a move of the app's that no frame has reported yet, as the
  /// frame would (a swap over the entry the browser is on, anything else
  /// past it), so what is reported next is told apart from it.
  void _reportPending() {
    if (_unreported) _report(inPlace: _replacing);
  }

  /// Whether the router holds a move of the app's that no frame has
  /// reported yet: a report leaves the provider what it reported, a move
  /// what it was asked.
  bool get _unreported =>
      _router.routeInformationProvider.value.state is RouteInformationState;

  /// Reports what the router shows, now rather than after the frame:
  /// written over the entry the browser is on where [inPlace], else as an
  /// entry past it.
  void _report({required bool inPlace}) {
    _unwritten = null;
    if (_router.routerDelegate.navigatorKey.currentContext == null) return;
    final shown = _router.routeInformationParser.restoreRouteInformation(
      _config,
    );
    if (shown == null) return;
    _router.routeInformationProvider.routerReportsNewRouteInformation(
      shown,
      type: inPlace
          ? RouteInformationReportingType.neglect
          : RouteInformationReportingType.none,
    );
  }

  /// Writes [passed], a move of the app's the router never reported, as
  /// its report would have: straight to the engine, so the router still
  /// holds the move made after it as unreported.
  void _write(RouteMatchList passed, {required bool inPlace}) {
    if (_router.routerDelegate.navigatorKey.currentContext == null) return;
    final shown = _router.routeInformationParser.restoreRouteInformation(
      passed,
    );
    if (shown == null) return;
    SystemNavigator.selectMultiEntryHistory();
    SystemNavigator.routeInformationUpdated(
      uri: shown.uri,
      state: shown.state,
      replace: inPlace,
    );
  }

  /// Has the router's next report, of what it answers a browser move it
  /// is about to hear of with, written over the entry the browser is on.
  void _neglectAnswer() {
    final host = _router.routerDelegate.navigatorKey.currentContext;
    if (host != null) Router.neglect(host, () {});
  }

  void _sample() => _seen = _browser!.position;

  /// Takes a browser move to an entry of a location forgotten and steps
  /// on past it the way it went, so the router never builds it: within a
  /// step back's own allowance, else [_strays] in a row, and never out of
  /// the app's entries: at the oldest what stands in for it is written
  /// over it, and from the newest, where the browser knows it is, it goes
  /// back to the entry the router is on (else that one is let through).
  /// One of a location that became another is not passed while a session
  /// is up: its visit is shown, written over it (see [_landOnKept]), unless
  /// what it became is forgotten in turn (see [_keptAt]).
  /// A pop's landing is its own, unless the list holds nothing behind and
  /// it lands on something forgotten: the push's base was taken out from
  /// under it. An entry of what is on screen is passed too: landing there
  /// would show nothing new (a router pop leaves one beside the page it
  /// left, a move the router made in place of a step leaves one beside the
  /// visit's own).
  bool _passOver(int at, int shown) {
    final browser = _browser!;
    final passed = _passed;
    _passed = null;
    final forgotten = _isForgotten(browser);
    // Which side of the entry the router is on the browser is: the way a
    // pass goes on, and how far a way back is. A landing asks which way
    // this one move went from the entry last read instead (below), as
    // [_mark] asks it for an arrival the router hears, so both take the
    // same neighbour of the cursor first. The two agree wherever the entry
    // the router is on is the one last read, or the one the engine pushed
    // just above it. Elsewhere (the engine written to more than once since
    // the last read, the edge [_landedOn] names) each keeps its own answer,
    // and a landing whose first neighbour is not its visit takes the other.
    final back = at < shown;
    // An entry of a location that became another (see [forget]) is its
    // visit's. Not signed out: the visits went with the session, and the
    // entry is passed with the others it left.
    final kept = _nowAt.isEmpty ? null : _keptAt(browser);
    if (kept != null && !_putsSignInUp(browser)) {
      _landOnKept(browser, kept, forward: at > _seen, passed: passed);
      return true;
    }
    // A pop the list holds steps on past a forgotten entry as the arrow
    // does: its base was taken out from under the page it pops.
    if (_arrowBack case final arrow?) {
      return forgotten && back && _stepOn(arrow);
    }
    if (_popping case final popping?) {
      // What the push was made over was taken out from under it since,
      // and the list holds nothing behind to pass to: the pop is the
      // router's, written over this entry.
      if (!forgotten || !back) return false;
      _popOver(popping);
      return true;
    }
    // Signed out, every entry the session left would put the sign-in
    // screen up again, as one more entry: passed with no limit, and out of
    // the app's entries where a page lies before them, since leaving is
    // what back means from a sign-in screen.
    if (_putsSignInUp(browser)) {
      _passed = passed ?? 0;
      if (back ? browser.canStepBack : browser.canStepForward) {
        _ask(back ? -1 : 1);
        return true;
      }
      if (back && browser.canLeave) {
        _ask(-1);
        return true;
      }
      // Nothing lies past it: shown, and what the redirect answers is
      // written over it.
      _passed = null;
      _neglectAnswer();
      return false;
    }
    if (!forgotten && !_isOnScreen(browser)) return false;
    final count = passed ?? 0;
    if (_passOn(count, forward: !back)) return true;
    // Its allowance spent, or no entry of the app lies that way.
    if (count >= _strays || !forgotten) return false;
    if (back) {
      // The app's oldest entry, which a pass never leaves the app from:
      // what stands in for it is written over it.
      _standInOver(browser, adjacent: shown - at == count + 1);
      return true;
    }
    // The newest, where the browser knows it is (after a reload that
    // kept nothing it cannot tell, and the entry is let through): the
    // browser goes back to the entry the router is on.
    if (!browser.newestKnown) return false;
    _returning = shown;
    _ask(shown - at);
    return true;
  }

  /// Has a browser move of the visitor's own step on past the entry it is
  /// on, the way it went, as one more than the [count] it has passed in a
  /// row; false, having asked nothing, at [_strays] or where no entry of
  /// the app lies that way.
  bool _passOn(int count, {required bool forward}) {
    final browser = _browser!;
    if (count >= _strays) return false;
    if (forward ? !browser.canStepForward : !browser.canStepBack) return false;
    _passed = count + 1;
    _ask(forward ? 1 : -1);
    return true;
  }

  /// Has [arrow] step on past an entry it did not want, as one more of its
  /// allowance; false, having asked nothing, where that is spent or no
  /// entry of the app lies behind. What its caller does then is its own:
  /// [_passOver] lets the router hear the entry, [_landOnKept] shows the
  /// visit there, and [_stepPast] (from the delegate's notification and
  /// [_mark]'s timer) restores the visit the step was after.
  bool _stepOn(_ArrowBack arrow) {
    if (arrow.strays <= 0 || !_browser!.canStepBack) return false;
    _arrowBack = arrow.withStrays(arrow.strays - 1);
    _ask(-1);
    return true;
  }

  /// Shows what stands in for the entry [browser] is on, which shows
  /// something forgotten, the router's way and written over that entry:
  /// for a location forgotten, see [_standInFor]; for a push, its base.
  /// [adjacent] where every entry between it and the one on screen was
  /// passed, so the list holds what stands in just behind. A move the app
  /// made just before, which the engine was never told of, goes first and
  /// is never written, as at any landing this history shows itself (see
  /// [_landOnKept]).
  void _standInOver(BrowserHistoryPort browser, {required bool adjacent}) {
    final to = _isGone(Uri.parse(browser.location).path)
        ? _standInFor(browser.location)
        : browser.location;
    _unhearOvertaken();
    _inPlace(
      () => _make(_StandIn(adjacent: adjacent), () => _router.go(to)),
      overtaking: true,
    );
    _sample();
  }

  /// What stands in for [location], which is forgotten: what it became
  /// (see [_became]), the page it is declared beneath, else its branch's
  /// root, else Home; the next one up where that is forgotten too.
  String _standInFor(String location) {
    var at = Uri.parse(location).path;
    for (var i = 0; i < 8; i++) {
      final to =
          _became(at) ??
          _router.declaredParentOf(at) ??
          _branchRootOf(at) ??
          WaxRoute.home;
      final path = Uri.parse(to).path;
      if (path == at) break;
      if (!_isGone(path)) return to;
      at = path;
    }
    return WaxRoute.home;
  }

  /// What [path] became: where it is at or beneath a location [forget]
  /// was told became another, and that one has not been visited since,
  /// the other with [path]'s tail, and what that became in turn. Null
  /// where it became nothing.
  String? _became(String path) {
    String? to;
    var at = path;
    for (var i = 0; i < 8; i++) {
      String? next;
      for (
        var end = at.length;
        end > 0 && next == null;
        end = at.lastIndexOf('/', end - 1)
      ) {
        final gone = at.substring(0, end);
        if (_nowAt[gone] case final kept? when _isGone(gone)) {
          next = Uri.parse(kept).path + at.substring(end);
        }
      }
      if (next == null || next == at) break;
      to = at = next;
    }
    return to;
  }

  /// The visit the entry [browser] is on is now, where a location in it
  /// became another (see [forget]), its own or a push's whatever lies over
  /// it: each at what it became, through every one that became another
  /// since, as the list's visits were moved (see [_asBecame]). Null where
  /// none did, or the table matches nothing there, or what it is now shows
  /// something forgotten since (the survivor deleted, a page open over it
  /// done with): the entry is then forgotten as any other, which the
  /// location it has says already.
  _Visit? _keptAt(BrowserHistoryPort browser) {
    final locations = browser.pushes;
    final keys = browser.pushKeys;
    if (keys.length != locations.length) return null;
    final to = _asBecame(Uri.parse(browser.location), [
      for (final (i, location) in locations.indexed)
        _Push(
          location: location,
          extra: null,
          pageKey: ValueKey<String>(keys[i]),
          navigator: _router.routerDelegate.navigatorKey,
          completer: null,
        ),
    ], _became);
    if (to == null) return null;
    final top = to.pushes.lastOrNull;
    if (_showsForgotten(
      to.root.toString(),
      top: top?.location,
      key: top?.pageKey.value,
    )) {
      return null;
    }
    final list = _rebuild(
      _Visit(
        root: to.root,
        extra: null,
        pushes: to.pushes,
        branch: null,
        pages: const <_Page>[],
        tabTap: false,
      ),
    );
    return list == null ? null : _visitOf(list);
  }

  /// Takes a browser move to an entry of a location that became another,
  /// where [kept] is the visit that entry is now (see [_keptAt]): the visit
  /// the list holds for it is shown in its place the router's way, so the
  /// page that went is never built, and written over the entry once the
  /// frame after has been (see [_writeHeldSoon]).
  ///
  /// A pop lands on it as on its base. A step back lands on it where it
  /// is the visit the step was after, and else steps on while it may. A
  /// move of the browser's own passes it where it is what is on screen,
  /// lands on the visit next to the cursor on the side it went
  /// ([forward]), then on the other, and on neither the list starts over
  /// there.
  ///
  /// A move the app made just before, in the same frame, which the engine
  /// was never told of, goes as it does where the router hears the
  /// browser's move itself: its visit leaves the list first (see
  /// [_unhearOvertaken]), so the cursor is where the browser left from,
  /// and the visit shown takes its place in the router with nothing
  /// reported of it, so it is never written and every entry ahead stays.
  void _landOnKept(
    BrowserHistoryPort browser,
    _Visit kept, {
    required bool forward,
    required int? passed,
  }) {
    final arrow = _arrowBack;
    if (_popping case final popping? when !forward) {
      _arrowBack = null;
      browser.hold();
      _writeHeldSoon(past: false);
      _popOver(popping);
      _sample();
      return;
    }
    int? to;
    if (arrow != null) {
      final after = math.min(arrow.index, _visits.length - 1);
      if (!_isVisitOf(after, kept, kept.root) && _stepOn(arrow)) return;
      _arrowBack = null;
      if (after >= 0) to = after;
    } else {
      final onScreen = _showsScreen(kept.root.toString(), [
        for (final push in kept.pushes) push.location,
      ]);
      if (onScreen && _passOn(passed ?? 0, forward: forward)) return;
      _unhearOvertaken();
      to = _beside(kept, kept.root, forward: forward);
    }
    final departed = _config;
    final list = to == null ? null : _rebuild(_visits[to]);
    browser.hold();
    _writeHeldSoon(past: false);
    if (list != null) {
      _inPlace(() => _routerStep(_RestoreTo(to!, list)), overtaking: true);
    } else if (_rebuild(kept) case final own?) {
      _inPlace(
        () =>
            _make(const _StandIn(adjacent: false), () => _router.restore(own)),
        overtaking: true,
      );
    }
    _sample();
    // As a landing does, for a push the move took off.
    _settle(departed, _config);
    _walked();
  }

  /// The root of the branch [path] is shown in, where it has one.
  String? _branchRootOf(String path) {
    final match = _router.configuration.findMatch(Uri.parse(path));
    if (match.isError) return null;
    final branch = _parts(match).branch;
    return branch == null ? null : _branchRoots.elementAtOrNull(branch);
  }

  /// Whether [path] is at or beneath a location [forget] was given.
  bool _isGone(String path) =>
      _forgotten.any((it) => _holds(path, it.path, anywhere: it.anywhere));

  /// Ends [popping], whose step landed on an entry of something forgotten,
  /// by the router's pop written over that entry, as its give-up does.
  void _popOver(_Popping popping) {
    _popping = null;
    if (_parts(_config).pushes.lastOrNull?.pageKey == popping.pageKey &&
        !pagelessOnTop) {
      _inPlace(() => _router.pop<Object?>(popping.result));
    }
    final push = popping.push;
    if (push.completer case final completer?
        when !completer.isCompleted && !push.mounted) {
      completer.complete(popping.result);
    }
    if (!popping.landed.isCompleted) popping.landed.complete();
    _settled();
  }

  /// Whether the entry [browser] is on shows something forgotten: its
  /// location, or the push on top, by where it is or by its page key. A
  /// push with another over it is not what the entry shows.
  bool _isForgotten(BrowserHistoryPort browser) => _showsForgotten(
    browser.location,
    top: browser.pushes.lastOrNull,
    key: browser.pushKeys.lastOrNull,
  );

  /// Whether [location], with the push [top] on top of it under the page
  /// key [key], shows something forgotten (see [_isForgotten]).
  bool _showsForgotten(
    String location, {
    required String? top,
    required String? key,
  }) {
    bool gone(String location) => _isGone(Uri.parse(location).path);

    return gone(location) ||
        (top != null && gone(top)) ||
        (key != null && _forgottenPushes.contains(key));
  }

  /// Whether the entry [browser] is on shows what the router does: its
  /// location, or one the router's redirect sends there, with the same
  /// pushes over it.
  bool _isOnScreen(BrowserHistoryPort browser) =>
      _showsScreen(browser.location, browser.pushes);

  /// Whether [location] with [pushed] over it is what the router shows
  /// (see [_isOnScreen]).
  bool _showsScreen(String location, List<String> pushed) {
    final pushes = [for (final push in _parts(_config).pushes) push.location];
    if (!listEquals(pushed, pushes)) return false;
    if (Uri.parse(location) == _config.uri) return true;
    return pushes.isEmpty && _resolved(location)?.uri == _config.uri;
  }

  /// Whether the entry [browser] is on would only put the sign-in screen
  /// up again: one the router's redirect answers with a sign-in screen (a
  /// location that needs a session, signed out), or an earlier sign-in
  /// entry the redirect answers with the one up.
  bool _putsSignInUp(BrowserHistoryPort browser) {
    final auth = WaxRoute.authLocations;
    final up = _config.uri.path;
    if (!auth.contains(up)) return false;
    final to = _resolved(browser.location)?.uri.path;
    if (to == null) return false;
    if (!auth.contains(Uri.parse(browser.location).path)) {
      return auth.contains(to);
    }
    return to == up &&
        listEquals(browser.pushes, [
          for (final push in _parts(_config).pushes) push.location,
        ]);
  }

  /// [location] as the router would answer a move there, its own redirect
  /// run on it; null where that has no answer at once.
  RouteMatchList? _resolved(String location) {
    final host = _router.routerDelegate.navigatorKey.currentContext;
    if (host == null) return null;
    final table = _router.configuration;
    final resolved = table.redirect(
      host,
      table.findMatch(Uri.parse(location)),
      redirectHistory: <RouteMatchList>[],
    );
    return resolved is RouteMatchList && !resolved.isError ? resolved : null;
  }

  /// A place visited again is somewhere back returns to: nothing that
  /// holds one of [visit]'s locations stays forgotten.
  void _visited(_Visit visit) {
    for (final push in visit.pushes) {
      _forgottenPushes.remove(push.pageKey.value);
    }
    _unforget(<String>[
      visit.root.path,
      for (final push in visit.pushes) Uri.parse(push.location).path,
    ]);
  }

  /// Nothing that holds one of [paths] stays forgotten.
  void _unforget(List<String> paths) {
    if (_forgotten.isEmpty) return;
    _forgotten.removeWhere(
      (it) => paths.any((path) => _holds(path, it.path, anywhere: it.anywhere)),
    );
  }

  /// Whether [path] is at or beneath [gone], or with [anywhere], ends with
  /// it or holds it followed by a `/`.
  static bool _holds(String path, String gone, {required bool anywhere}) =>
      anywhere
      ? path.endsWith(gone) || path.contains('$gone/')
      : path == gone || path.startsWith('$gone/');

  /// Moves the cursor to the visit a browser move landed on. A step back's
  /// own lands on the visit it was after and nowhere else; anything else
  /// is stepped past: an entry the list does not hold (a location it
  /// forgot, a page a router pop left behind it), or holds for a visit
  /// ahead, which is a page closed, or for one further back, which is a
  /// copy the browser kept (a push a tab tap brought back). A visit behind
  /// the one it was after that the entry cannot tell from it matches only
  /// where that one does.
  /// Otherwise the visit next to the cursor on the side the browser went
  /// ([forward]), then on the other; on neither the list starts over
  /// there.
  void _browserArrived(
    _Visit arriving,
    _ArrowBack? arrow, {
    required bool forward,
  }) {
    if (_cursor < 0) {
      _add(arriving);
      return;
    }
    final entry = _router.routeInformationProvider.value.uri;
    if (arrow != null) {
      final after = math.min(arrow.index, _visits.length - 1);
      if (_isVisitOf(after, arriving, entry)) {
        _land(after, arriving);
        return;
      }
      if (_stepPast(arrow)) {
        // Shown until the step it asked lands.
        if (_arrowBack != null) _strayShown = arriving;
        return;
      }
    }
    if (_beside(arriving, entry, forward: forward) case final index?) {
      _land(index, arriving);
      return;
    }
    // Each branch's last visit stays, as go_router's branch stacks do, so
    // a tab tap still leaves out what was forgotten.
    _visits.clear();
    _cursor = -1;
    _changes.changed();
    _add(arriving);
  }

  /// Whether the visit at [index] is the one a browser move to the entry
  /// at [entry], which shows [arriving], landed on (see
  /// [_Visit.isEntryOf]); false past either end of the list.
  bool _isVisitOf(int index, _Visit arriving, Uri entry) =>
      index >= 0 &&
      index < _visits.length &&
      _visits[index].isEntryOf(arriving, entry);

  /// The visit a browser move of the visitor's own landed on, where the
  /// entry at [entry] shows [arriving]: the one next to the cursor on the
  /// side the browser went ([forward]), then on the other, then the one at
  /// the cursor. Null where it is none of them.
  int? _beside(_Visit arriving, Uri entry, {required bool forward}) {
    final (near, far) = forward
        ? (_cursor + 1, _cursor - 1)
        : (_cursor - 1, _cursor + 1);
    return <int>[
      near,
      far,
      _cursor,
    ].where((index) => _isVisitOf(index, arriving, entry)).firstOrNull;
  }

  /// Steps past an entry [arrow] did not want, while it may, and else
  /// restores the visit it was after the router's way; false where that
  /// visit no longer resolves.
  bool _stepPast(_ArrowBack arrow) {
    if (_stepOn(arrow)) return true;
    final after = math.min(arrow.index, _visits.length - 1);
    if (after < 0) return false;
    if (_rebuild(_visits[after]) case final list?) {
      // Out of the delegate's notification, which this is inside.
      scheduleMicrotask(
        () => _inPlace(() => _routerStep(_RestoreTo(after, list))),
      );
      return true;
    }
    return false;
  }

  void _land(int index, _Visit arriving) {
    final was = _visits[index];
    // The entry's pushes come with fresh completers, so whoever awaits
    // the one it had hears through the new one.
    for (final push in arriving.pushes) {
      final kept = was.pushes
          .where((recorded) => recorded.pageKey == push.pageKey)
          .firstOrNull;
      final awaited = kept?.awaited;
      final fresh = push.completer;
      if (awaited == null || fresh == null || identical(awaited, fresh)) {
        continue;
      }
      unawaited(
        fresh.future.then((value) {
          if (!awaited.isCompleted) awaited.complete(value);
        }),
      );
    }
    final kept = arriving.keeping(was);
    _visits[index] = kept.marked(was.tabTap);
    _cursor = index;
    if (!identical(kept, arriving)) _repair(index);
  }

  /// Puts back the payloads the entry on screen dropped, from the visit at
  /// [index], before the frame builds the pages that read them. In place,
  /// so the browser rewrites that entry rather than adding one.
  void _repair(int index) {
    scheduleMicrotask(() {
      final host = _router.routerDelegate.navigatorKey.currentContext;
      if (_cursor != index || host == null) return;
      final list = _rebuild(_visits[index]);
      if (list == null) return;
      _inPlace(
        () => _make(_StepTo(index), () => _router.restore(list), settle: true),
      );
    });
  }

  /// Answers each push a browser move took off the screen: a restore
  /// completes nothing, so whoever awaits one would wait forever. With
  /// null, or for the push a browser pop took off, with what it popped
  /// with. Read after the frame that builds the arrival, as a branch left
  /// offstage keeps its pages, and its push is still somebody's to answer.
  void _settle(RouteMatchList departed, RouteMatchList arrived) {
    final held = {for (final push in _parts(arrived).pushes) push.pageKey};
    final gone = [
      for (final push in _parts(departed).pushes)
        if (!held.contains(push.pageKey)) push,
    ];
    if (gone.isEmpty) return;
    final popping = _popping;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final push in gone) {
        if (push.completer case final completer?
            when !completer.isCompleted && !push.mounted) {
          completer.complete(
            push.pageKey == popping?.pageKey
                ? popping!.result
                : _carried.remove(push.pageKey),
          );
        }
      }
    });
  }

  int? _target(_Visit? here) {
    for (var i = _cursor; i >= 0; i--) {
      final visit = _visits[i];
      if (here != null && visit.sameAs(here)) continue;
      if (_rebuild(visit) == null) continue;
      return i;
    }
    return null;
  }

  /// Runs [navigate] as [move]. With [settle], a move the router answers
  /// with no change (a redirect sent the visit back to what is on screen)
  /// still lands where it was going.
  void _make(_Move move, VoidCallback navigate, {bool settle = false}) {
    _moving = move;
    try {
      navigate();
    } finally {
      // No answer within the call is read as no change, which holds while
      // every redirect is synchronous and no route has an `onExit`. Either
      // answers later, and would be recorded as a visit of its own.
      final unanswered = identical(_moving, move);
      _moving = null;
      if (unanswered && settle) {
        final here = _visitOf(_config);
        if (here != null) {
          _arrive(move, here);
          // The router reports no arrival for it.
          _changes.changed();
        }
      }
    }
  }

  void _arrive(_Move move, _Visit arriving) {
    switch (move) {
      case _StepTo(:final index) when index < _visits.length:
        _visits[index] = arriving.marked(_visits[index].tabTap);
        _cursor = index;
      case _StepTo():
        _add(arriving);
      case _Climb(:final outward):
        if (_cursor < 0) {
          _add(arriving.marked(outward));
          return;
        }
        _visits[_cursor] = arriving.marked(outward || _visits[_cursor].tabTap);
      case _StandIn(:final adjacent):
        if (adjacent && _cursor >= 0) {
          _insertAtCursor(arriving);
          return;
        }
        _visits.clear();
        _cursor = -1;
        _changes.changed();
        _add(arriving);
    }
  }

  /// Puts [visit] just behind the visit at the cursor, which is then on
  /// it. Past [_bound] the oldest goes, as [_add] drops it, where one lies
  /// behind [visit]; where none does, nothing goes (neither [visit] nor
  /// the visits ahead, which the browser's forward walks), and the list
  /// stays one over until the next visit added trims it from the front.
  void _insertAtCursor(_Visit visit) {
    _visits.insert(_cursor, visit);
    if (_visits.length > _bound && _cursor > 0) {
      _visits.removeAt(0);
      _cursor--;
    }
  }

  void _add(_Visit visit) {
    _visits
      ..removeRange(_cursor + 1, _visits.length)
      ..add(visit);
    if (_visits.length > _bound) {
      _visits.removeRange(0, _visits.length - _bound);
    }
    _cursor = _visits.length - 1;
  }

  void _drop(int index) {
    _visits.removeAt(index);
    if (index <= _cursor) _cursor--;
    // A step under way stays after its visit, or after the one behind a
    // visit that went.
    if (_arrowBack case final arrow? when index <= arrow.index) {
      _arrowBack = _ArrowBack(
        arrow.index - 1,
        strays: arrow.strays,
        from: arrow.from,
      );
    }
  }

  bool get _replacing {
    final state = _router.routeInformationProvider.value.state;
    return state is RouteInformationState &&
        (state.type == NavigatingType.replace ||
            state.type == NavigatingType.pushReplacement);
  }

  /// [visit]'s match list as the table matches it now, each push with the
  /// page key it had, so a page still mounted keeps its state, and the
  /// completer it can be awaited through. Null when the table no longer
  /// matches a location in it.
  RouteMatchList? _rebuild(_Visit visit) {
    final table = _router.configuration;
    var list = table.findMatch(visit.root, extra: visit.extra);
    if (list.isError) return null;
    for (final push in visit.pushes) {
      final pushed = table.findMatch(
        Uri.parse(push.location),
        extra: push.extra,
      );
      if (pushed.isError) return null;
      list = list.push(
        ImperativeRouteMatch(
          pageKey: push.pageKey,
          matches: pushed,
          completer: push.resumable,
        ),
      );
    }
    return list;
  }

  _Visit? _visitOf(RouteMatchList config, {bool tabTap = false}) {
    if (config.isEmpty || config.isError) return null;
    if (WaxRoute.authLocations.contains(config.uri.path)) return null;
    final (:pushes, :pages, :branch) = _parts(config);
    return _Visit(
      root: config.uri,
      extra: config.extra,
      pushes: pushes,
      branch: branch,
      pages: pages,
      tabTap: tabTap,
    );
  }

  /// [config]'s pushes and pages in tree order, and the branch it shows.
  ({List<_Push> pushes, List<_Page> pages, int? branch}) _parts(
    RouteMatchList config,
  ) {
    final pushes = <_Push>[];
    final pages = <_Page>[];
    int? branch;
    void walk(
      List<RouteMatchBase> matches,
      GlobalKey<NavigatorState> navigator,
    ) {
      for (final match in matches) {
        switch (match) {
          case ShellRouteMatch():
            if (match.route case final StatefulShellRoute shell) {
              branch = shell.branches.indexWhere(
                (candidate) => candidate.navigatorKey == match.navigatorKey,
              );
            }
            pages.add((key: match.navigatorKey, location: '', pushed: false));
            walk(match.matches, match.navigatorKey);
          case ImperativeRouteMatch():
            final location = match.matches.uri.toString();
            pushes.add(
              _Push(
                location: location,
                extra: match.matches.extra,
                pageKey: match.pageKey,
                navigator: navigator,
                completer: match.completer,
              ),
            );
            pages.add((key: match.pageKey, location: location, pushed: true));
          case RouteMatch():
            pages.add((
              key: match.pageKey,
              location: match.matchedLocation,
              pushed: false,
            ));
        }
      }
    }

    walk(config.matches, _router.routerDelegate.navigatorKey);
    return (pushes: pushes, pages: pages, branch: branch);
  }
}

/// Keeps the route each page of its navigator has, so a page the history
/// takes out from under what is on top leaves at once: removed by the
/// router alone it would leave with its exit transition, held while
/// something opaque covers its navigator and played once that goes.
/// One to a navigator.
class PageRoutes extends NavigatorObserver {
  static final _routes = <LocalKey, Route<Object?>>{};

  /// The route [key]'s page has, while it is in its navigator.
  static Route<Object?>? of(Object key) => switch (_routes[key]) {
    final route? when route.isActive => route,
    _ => null,
  };

  static void _add(Route<Object?>? route) {
    if (route?.settings case Page<Object?>(:final key?)) {
      _routes[key] = route!;
      // A navigator gone with its pages tells nobody.
      if (_routes.length > 200) {
        _routes.removeWhere((_, kept) => kept.navigator == null);
      }
    }
  }

  static void _remove(Route<Object?>? route) {
    if (route?.settings case Page<Object?>(
      :final key?,
    ) when identical(_routes[key], route)) {
      _routes.remove(key);
    }
  }

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
      _add(route);

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    _remove(oldRoute);
    _add(newRoute);
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) =>
      _remove(route);

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) =>
      _remove(route);
}

/// A page on screen as back and a delete tell pages apart: where it is,
/// and its key, which tells two pushes of one location apart. go_router
/// keys a page it builds from the table by its route's pattern, so by
/// the key alone any two books are one page.
typedef PageId = ({String location, LocalKey key});

/// The page on top of [router]'s screen, under whatever is open over it.
PageId? pageOnTop(GoRouter router) =>
    switch (router.routerDelegate.currentConfiguration.lastOrNull) {
      final match? => (location: match.matchedLocation, key: match.pageKey),
      null => null,
    };

/// Whether the page on top of [router]'s screen is one [own] picks out,
/// for work that navigates once the server has answered: a visitor who
/// went elsewhere meanwhile keeps their screen. Where it is, whatever was
/// opened over it meanwhile is closed first, so a leave takes the page
/// rather than that, and a move is made from the page itself. Read once a
/// step on its way has landed, as natively it would have already.
Future<bool> stillOnTop(GoRouter router, bool Function(PageId page) own) async {
  final history = WaxHistory.of(router);
  if (history?.landing case final landing?) await landing;
  final top = pageOnTop(router);
  if (top == null || !own(top)) return false;
  if (history != null && history.pagelessOnTop) await history.closePageless();
  return true;
}

/// Whether the visitor is still on [from] with nothing opened over it,
/// for work that shows what they asked to see once the server has
/// answered. Anywhere else (another page, or a sheet, dialog or menu
/// opened over it meanwhile) is where they went, and what they asked for
/// is offered there instead of shown over it. Read once a step on its way
/// has landed.
Future<bool> stillShowing(GoRouter router, PageId? from) async {
  if (WaxHistory.of(router)?.landing case final landing?) await landing;
  return from != null &&
      pageOnTop(router) == from &&
      _pagelessTopOf(router) == null;
}

/// The route that is not a page on top of the topmost navigator on
/// [router]'s screen that has one.
Route<Object?>? _pagelessTopOf(GoRouter router) {
  Route<Object?>? covering(NavigatorState? navigator) {
    final top = _topRoute(navigator);
    return top?.settings is Page<Object?> ? null : top;
  }

  final delegate = router.routerDelegate;
  if (covering(delegate.navigatorKey.currentState) case final top?) {
    return top;
  }
  RouteMatchBase? walker = delegate.currentConfiguration.matches.lastOrNull;
  while (walker is ShellRouteMatch) {
    if (covering(walker.navigatorKey.currentState) case final top?) {
      return top;
    }
    walker = walker.matches.lastOrNull;
  }
  return null;
}

/// The route on top of [navigator].
Route<Object?>? _topRoute(NavigatorState? navigator) {
  Route<Object?>? top;
  // A predicate that holds at once pops nothing.
  navigator?.popUntil((route) {
    top = route;
    return true;
  });
  return top;
}

/// Makes sure a page whose work finished while the visitor was elsewhere
/// is never shown again: the page at [location] gone to with [extra] is
/// taken out from under what is on top, and every visit of it forgotten,
/// so neither back, the browser's forward, nor a tab tap brings it back.
void forgetFinished(GoRouter router, String location, Object? extra) {
  final history = WaxHistory.of(router);
  if (history == null) return;
  final path = Uri.parse(location).path;
  history
    ..takeOutFromUnder(
      (at, gone) => Uri.parse(at).path == path && gone == extra,
    )
    ..forget(path, where: (gone) => gone == extra);
}

/// Closes [route], a dialog or sheet whose work is done, with [result]:
/// by a pop while it is on top, else taken out from under what was
/// opened over it, so it is never shown again. Nothing where it has gone
/// already (dismissed while the work ran, or on its way out), as a pop
/// would take what lies under it.
void closeFinished<T>(Route<T>? route, [T? result]) {
  final navigator = route?.navigator;
  if (route == null || navigator == null || !route.isActive) return;
  if (route.isCurrent) {
    navigator.pop<T>(result);
  } else {
    navigator.removeRoute<T>(route, result);
  }
}

/// The page [context] is in, told apart as [pageOnTop] tells them. Under
/// a page the router built.
PageId pageIn(BuildContext context) {
  final state = GoRouterState.of(context);
  return (location: state.matchedLocation, key: state.pageKey);
}

/// What the page on top of [router]'s screen was gone to with: a push's
/// own extra, or its location's.
Object? extraOnTop(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  return switch (config.lastOrNull) {
    final ImperativeRouteMatch push => push.matches.extra,
    _ => config.extra,
  };
}

/// One page of a visit, in tree order: a shell's navigator, or a page
/// with its key and where it is.
typedef _Page = ({Object key, String location, bool pushed});

/// A visit a move of the app's added, its branch's last visit before it,
/// where one was [known], and the visits [ahead] it took the place of.
typedef _Added = ({_Visit visit, bool known, _Visit? last, List<_Visit> ahead});

/// A move of the app's the engine was not told of: the visit it [added],
/// none for one that adds none (a swap, a step up), and whether it is
/// written over the entry it was made on ([inPlace], a swap) or past it.
typedef _Unheard = ({_Added? added, bool inPlace});

/// A push on top of a visit's root: where it went, with what, and under
/// which page key in which navigator.
final class _Push {
  _Push({
    required this.location,
    required this.extra,
    required this.pageKey,
    required this.navigator,
    required this._completer,
  });

  final String location;
  final Object? extra;
  final ValueKey<String> pageKey;
  final GlobalKey<NavigatorState> navigator;

  /// What the push's caller awaits, until a visit lets it go (see
  /// [release]). Not part of what makes two pushes the same: go_router
  /// decodes a list again with fresh ones on a refresh.
  Completer<Object?>? get completer => _completer;
  Completer<Object?>? _completer;

  /// Lets go of [completer] once it can no longer be reused, answered or
  /// its page gone, so a visit kept does not keep the caller's
  /// continuation, and what that holds, alive.
  void release() {
    final completer = _completer;
    if (completer != null && (completer.isCompleted || !mounted)) {
      _completer = null;
    }
  }

  /// Whether its page is in its navigator, which a branch left for
  /// another keeps.
  bool get mounted =>
      navigator.currentState?.widget.pages.any((page) => page.key == pageKey) ??
      false;

  /// The same push made with [extra].
  _Push withExtra(Object? extra) => _Push(
    location: location,
    extra: extra,
    pageKey: pageKey,
    navigator: navigator,
    completer: completer,
  );

  /// Its completer while somebody can still hear it: unanswered, and its
  /// page still mounted, since a page that went took its caller with it.
  Completer<Object?>? get awaited => switch (_completer) {
    final completer? when !completer.isCompleted && mounted => completer,
    _ => null,
  };

  /// The completer to rebuild the push with: [awaited], so the caller
  /// hears back, or a fresh one, since an answered one throws when popped
  /// again.
  Completer<Object?> get resumable => awaited ?? Completer<Object?>();

  @override
  bool operator ==(Object other) =>
      other is _Push &&
      other.location == location &&
      other.extra == extra &&
      other.pageKey == pageKey;

  @override
  int get hashCode => Object.hash(location, extra, pageKey);
}

/// A match list taken apart: the location and extra its root was gone to
/// with, each push on top in order, and the branch it shows.
@immutable
class _Visit {
  const _Visit({
    required this.root,
    required this.extra,
    required this.pushes,
    required this.branch,
    required this.pages,
    required this.tabTap,
  });

  final Uri root;
  final Object? extra;
  final List<_Push> pushes;
  final int? branch;
  final List<_Page> pages;

  /// Made by the navigation chrome rather than by a screen.
  final bool tabTap;

  _Visit marked(bool tabTap) => tabTap == this.tabTap
      ? this
      : _Visit(
          root: root,
          extra: extra,
          pushes: pushes,
          branch: branch,
          pages: pages,
          tabTap: tabTap,
        );

  /// This, a browser entry's, with each extra the entry dropped taken
  /// from [recorded]: the root's where it is the same location, each
  /// push's by its page key.
  _Visit keeping(_Visit recorded) {
    final byKey = {for (final push in recorded.pushes) push.pageKey: push};
    final kept = [
      for (final push in pushes)
        push.extra == null && byKey[push.pageKey]?.extra != null
            ? push.withExtra(byKey[push.pageKey]!.extra)
            : push,
    ];
    final keepsRoot =
        extra == null && recorded.extra != null && root == recorded.root;
    if (!keepsRoot && listEquals(kept, pushes)) return this;
    return _Visit(
      root: root,
      extra: keepsRoot ? recorded.extra : extra,
      pushes: kept,
      branch: branch,
      pages: pages,
      tabTap: tabTap,
    );
  }

  bool sameAs(_Visit other) =>
      root == other.root &&
      extra == other.extra &&
      branch == other.branch &&
      listEquals(pushes, other.pushes);

  /// Whether [other] shows these pages, whatever it was gone to with.
  bool samePages(_Visit other) => listEquals(pages, other.pages);

  /// Whether [arriving], a browser move to the entry at [entry], is this
  /// visit. An entry keeps the location and each push's location and page
  /// key, not an extra it cannot encode; where a redirect moved the
  /// arrival elsewhere, the entry's location is all that says where it was.
  bool isEntryOf(_Visit arriving, Uri entry) {
    if (arriving.root.path != entry.path) return root.path == entry.path;
    if (root != arriving.root || branch != arriving.branch) return false;
    if (pushes.length != arriving.pushes.length) return false;
    for (var i = 0; i < pushes.length; i++) {
      final (mine, theirs) = (pushes[i], arriving.pushes[i]);
      if (mine.location != theirs.location || mine.pageKey != theirs.pageKey) {
        return false;
      }
    }
    return true;
  }

  /// Whether [other] is this with pages on top, whatever it was gone to
  /// with.
  bool isAncestorPagesOf(_Visit other) =>
      pages.length < other.pages.length &&
      listEquals(pages, other.pages.sublist(0, pages.length));

  /// Whether [other] is this with pages on top, gone to with this one's
  /// query and extra.
  bool isAncestorOf(_Visit other) =>
      _sameQuery(other) && isAncestorPagesOf(other);

  /// Whether [other] is this with one push on top.
  bool isUnderOnePush(_Visit other) =>
      other.pages.length == pages.length + 1 &&
      other.pages.last.pushed &&
      isAncestorOf(other);

  // A change to either is somewhere else, whatever pages it keeps. A pop
  // keeps both: go_router carries the root's query and extra down, so the
  // visit a pop returns to is matched by its pages alone.
  bool _sameQuery(_Visit other) =>
      root.query == other.root.query && extra == other.extra;
}

/// A move this history makes, and so reads the change it causes against.
sealed class _Move {
  const _Move();
}

/// A step back to the visit at [index].
final class _StepTo extends _Move {
  const _StepTo(this.index);

  final int index;
}

/// A step out with nowhere recorded to return to.
final class _Climb extends _Move {
  const _Climb({required this.outward});

  final bool outward;
}

/// What a browser landing shows in place of the entry it is on, where the
/// list holds no visit for it. For an entry of something forgotten, what
/// stands in: a visit just behind the one on screen where every entry
/// between was passed ([adjacent]), else where the list starts over. For
/// an entry of a location that became another whose visit is not beside
/// the cursor, nothing stands in: what the entry is now is shown (see
/// [WaxHistory._landOnKept]), and the list starts over there.
final class _StandIn extends _Move {
  const _StandIn({required this.adjacent});

  final bool adjacent;
}

/// A step back through the browser: the visit at [index] it is after, and
/// how many more entries the list does not hold it may step past.
final class _ArrowBack {
  const _ArrowBack(this.index, {required this.strays, required this.from});

  final int index;
  final int strays;

  /// The browser's position for the entry the step was asked from.
  final int from;

  /// The same step with [strays] left.
  _ArrowBack withStrays(int strays) =>
      _ArrowBack(index, strays: strays, from: from);
}

/// A browser back or forward, and which it was.
final class _BrowserMove {
  const _BrowserMove({required this.forward});

  final bool forward;
}

/// What a landing holds for the frame after it (see
/// [WaxHistory._writeHeldSoon]), told apart from another landing's.
final class _HeldWrite {
  _HeldWrite({required this.over});

  /// The browser's position for the entry it is written over, which the
  /// landing put the router on; null where it goes past the one landed on.
  final int? over;
}

/// A pop the browser makes: the push it takes off, with the completer
/// its opener awaits, what that opener hears, and the step's landing.
final class _Popping {
  _Popping(this.push, this.result, {required this.from});

  final _Push push;
  final Object? result;

  /// How many more entries of something forgotten it may pass where the
  /// app's own move overtook it.
  var strays = WaxHistory._strays;

  /// The browser's position for the push's own entry.
  final int from;
  final landed = Completer<void>();

  ValueKey<String> get pageKey => push.pageKey;
}

/// What a back does, decided before it is made.
sealed class _BackStep {
  const _BackStep();
}

/// Pops the one push that lies over the visit at [index].
final class _PopTo extends _BackStep {
  const _PopTo(this.index);

  final int index;
}

/// Restores the visit at [index], rebuilt as [list].
final class _RestoreTo extends _BackStep {
  const _RestoreTo(this.index, this.list);

  final int index;
  final RouteMatchList list;
}

/// Pops the page on top, with nothing recorded under it.
final class _PopUp extends _BackStep {
  const _PopUp();
}

/// Goes up to [location] with nothing recorded to return to.
final class _GoUp extends _BackStep {
  const _GoUp(this.location);

  final String location;
}

final class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}
