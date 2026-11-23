import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../library/page_walk.dart';

export '../library/page_walk.dart' show PagedRows, walkRows;

/// How deep a paged listing's refresh reads.
enum CatalogRefresh {
  /// The first pages. Rows past them are kept as they were held.
  head,

  /// The whole loaded extent, once.
  loaded,
}

/// The depth each paged listing's next refresh owes, kept apart from the
/// listings themselves: every read path riverpod exposes flushes a dirty
/// element, `.notifier` included, so telling a covered listing through
/// its notifier would be a fetch nobody asked for. The strongest depth
/// owed stands, through a pause of any length, until a build takes it.
class OwedDepths {
  OwedDepths(this._container);

  final ProviderContainer _container;
  final _owed = <ProviderBase<Object?>, CatalogRefresh>{};

  /// Tells [listing] its next refresh owes [depth]. One that is not
  /// there has nothing to refresh, and its first read is the head.
  void owe(ProviderBase<Object?> listing, CatalogRefresh depth) {
    if (!_container.exists(listing)) return;
    final standing = _owed[listing];
    if (standing == null || depth.index > standing.index) {
      _owed[listing] = depth;
    }
  }

  /// What [listing] owes, cleared: for the build that honours it.
  CatalogRefresh? take(ProviderBase<Object?> listing) => _owed.remove(listing);

  /// Drops what is owed to listings that have gone.
  void prune() =>
      _owed.removeWhere((listing, _) => !_container.exists(listing));
}

final owedDepthsProvider = Provider<OwedDepths>(
  (ref) => OwedDepths(ref.container),
);

/// The paged listings whose last refresh failed with none landed since,
/// kept apart from them for the reason [OwedDepths] is. Each listing
/// files and clears itself.
class FailedRefreshes {
  FailedRefreshes(this._container);

  final ProviderContainer _container;
  final _failed = <ProviderBase<Object?>>{};

  void failed(ProviderBase<Object?> listing) => _failed.add(listing);

  void landed(ProviderBase<Object?> listing) => _failed.remove(listing);

  /// Whether [listing]'s last refresh failed and none has landed since.
  bool failedLast(ProviderBase<Object?> listing) =>
      _failed.contains(listing) && _container.exists(listing);

  /// Drops listings that have gone.
  void prune() => _failed.removeWhere((listing) => !_container.exists(listing));
}

final failedRefreshesProvider = Provider<FailedRefreshes>(
  (ref) => FailedRefreshes(ref.container),
);

/// A fresh read of a listing's head laid over the rows [held]: the fresh
/// rows, then the held rows after the last fresh row the held list also
/// has, less anything the head holds. A cut by position would drop rows
/// whenever the head grew, which is every scan.
///
/// Paging goes on from the kept tail's cursor, or from the head's own
/// where no tail is kept. A head that reached the listing's end is the
/// whole listing. So is one that holds no row of the held list: nothing
/// says where the held rows resume, and a list with a hole in it is worse
/// than a shorter one. A head with no rows in it and pages left unread
/// says nothing, and the held list stands.
PagedRows<RowT> spliceHead<RowT>({
  required PagedRows<RowT> fresh,
  required PagedRows<RowT> held,
  required Object Function(RowT row) keyOf,
}) {
  if (fresh.nextCursor == null) return fresh;
  if (fresh.rows.isEmpty) return held;
  final heldAt = <Object, int>{
    for (final (at, row) in held.rows.indexed) keyOf(row): at,
  };
  for (var i = fresh.rows.length - 1; i >= 0; i--) {
    final seam = heldAt[keyOf(fresh.rows[i])];
    if (seam == null) continue;
    final head = <Object>{for (final row in fresh.rows) keyOf(row)};
    final tail = <RowT>[
      for (final row in held.rows.skip(seam + 1))
        if (!head.contains(keyOf(row))) row,
    ];
    if (tail.isEmpty) return fresh;
    return (rows: <RowT>[...fresh.rows, ...tail], nextCursor: held.nextCursor);
  }
  return fresh;
}

/// How close together two passes of a catalog refresh may come. Owned
/// here, where the binder that paces by it reads it: this file cannot
/// import that one.
const kRefreshWindow = Duration(seconds: 5);

/// How long a refresh that failed waits before it is asked again, the
/// first time. Twice as long each time after, [kRefreshRetries] times at
/// most. Only those timed attempts are counted: a refresh asked from
/// outside (a hint's pass, a write) that fails starts the count over.
const kRefreshRetryAfter = kRefreshWindow;

const kRefreshRetries = 5;

enum _Honoured { applied, failed, dropped }

/// A paged listing that a refresh re-reads in place rather than from its
/// first page: riverpod keeps the notifier across an invalidation, so the
/// rows it holds are there to refresh.
///
/// One read is out at a time. A refresh that starts while a page or an
/// earlier refresh is in flight waits for it, and a next page waits for a
/// refresh: a pass that restarted the walk before it would never settle
/// while hints keep coming, and two reads at once would each lay their
/// rows over the other's. The listing is held here, not read back from
/// `state`, which flushes a dirty element.
mixin RefreshedInPlace<RowT, StateT> on AsyncNotifier<StateT> {
  /// The provider this notifier is: what its owed depth is filed under.
  @protected
  ProviderBase<Object?> get self;

  /// How many rows a full page holds.
  @protected
  int get pageRows;

  /// How many pages a first read or a next page may take to find a row:
  /// null to read on for as long as pages come back empty.
  @protected
  int? get walkLimit => null;

  /// What makes two reads of one row the same row.
  @protected
  Object rowKey(RowT row);

  /// The state a screen draws for [held].
  @protected
  StateT shape(PagedRows<RowT> held, {required bool loadingMore});

  /// Reads pages from [from], the listing's head when null, as
  /// [walkRows] does.
  @protected
  Future<PagedRows<RowT>> readRows({
    required int want,
    String? from,
    int? maxPages,
    bool Function()? stop,
  });

  /// The listing starts over: for what a notifier keeps beside its rows.
  @protected
  void startingOver() {}

  PagedRows<RowT>? _held;
  Object? _source;
  var _paging = false;

  /// Whether the listing is being read from its head.
  var _heading = false;
  Future<void>? _reading;

  /// Moves when the listing is replaced, so a read begun for the one
  /// before drops what it brings.
  var _epoch = 0;

  /// Moves when the listing starts over: read whole from its head, it
  /// owes nothing a read begun before that would owe back.
  var _starts = 0;

  /// Reads asked of the listing, counted as each begins: a refresh that
  /// took its depth, or a read from the head. [_out] is the one in
  /// flight, [_queued] the builds waiting behind a read to begin theirs.
  var _passes = 0;
  int? _out;
  var _queued = 0;
  final _awaited = <int, Completer<void>>{};

  /// Asks again after a refresh that failed, and how many times it has
  /// since one landed or was asked from outside.
  Timer? _retry;
  var _retries = 0;

  /// Whether the next refresh is the one [_retry] asked for.
  var _timed = false;

  /// The ref a disposal listener is set on.
  Ref? _heard;

  bool _stale(int epoch) => epoch != _epoch || !ref.mounted;

  int _begin() => _out = ++_passes;

  /// A refresh landed, or the listing was read whole: nothing to ask
  /// again, and the next failure waits the first wait.
  void _settled() {
    _retry?.cancel();
    _retry = null;
    _retries = 0;
    _timed = false;
    if (ref.mounted) ref.read(failedRefreshesProvider).landed(self);
  }

  /// Hears the listing's disposal, to answer what waits in [refreshed].
  /// Riverpod spends a build's listeners at its first invalidation, so
  /// one is set again after each while anything waits: a listing marked
  /// and then disposed before it builds again is heard too.
  void _hearDisposal() {
    final heard = ref;
    if (!heard.mounted) return _release();
    if (identical(_heard, heard)) return;
    _heard = heard;
    heard.onDispose(() {
      if (identical(_heard, heard)) _heard = null;
      // An invalidation asks now what the timer would have asked later.
      _retry?.cancel();
      _retry = null;
      // Unmounted here only when disposed.
      if (!heard.mounted) return _release();
      // In a turn of its own: riverpod refuses a ref inside a callback.
      if (_awaited.isNotEmpty) scheduleMicrotask(_hearDisposal);
    });
  }

  /// Nothing a waiter waits for will happen.
  void _release() {
    for (final done in _awaited.values) {
      done.complete();
    }
    _awaited.clear();
  }

  /// Asks again after a refresh that failed: an invalidation, so a
  /// listing nobody watches is only marked. One timer at a time; an
  /// invalidation that arrives first cancels it and takes its place.
  /// [timed] is whether the refresh that failed was the timer's own:
  /// one asked from outside is not an attempt of the retry, and the
  /// waits start over after it.
  void _askAgain({required bool timed}) {
    _retry?.cancel();
    _retry = null;
    if (!timed) _retries = 0;
    if (_retries >= kRefreshRetries) return;
    final wait = kRefreshRetryAfter * (1 << _retries);
    _retries++;
    _retry = Timer(wait, () {
      _retry = null;
      if (!ref.mounted) return;
      _timed = true;
      ref.invalidateSelf();
    });
  }

  /// [landed] is false for a pass the listing was replaced under: what
  /// waits on it waits on the pass that follows.
  void _end(int pass, {required bool landed}) {
    if (_out == pass) _out = null;
    if (!landed) return;
    _awaited.removeWhere((awaited, done) {
      if (awaited > pass) return false;
      done.complete();
      return true;
    });
  }

  /// The listing once the refresh asked of it as of now has landed or
  /// failed, null when no rows are held: the pass a build is waiting to
  /// begin, else the one in flight, else at once. Neither the provider's
  /// future nor a state that stops loading says as much: a page that
  /// lands while a refresh waits behind it settles both.
  ///
  /// Reading the notifier to call this starts a refresh still pending.
  /// A listing nobody listens to keeps the caller waiting until it is
  /// read again; one that is disposed answers null, marked first or not.
  Future<StateT?> refreshed() async {
    if (!ref.mounted) return null;
    final pass = _queued > 0 ? _passes + 1 : _out;
    if (pass != null) {
      final landed = (_awaited[pass] ??= Completer<void>()).future;
      _hearDisposal();
      await landed;
    }
    final held = _held;
    if (held == null || !ref.mounted) return null;
    return shape(held, loadingMore: _paging);
  }

  /// Tells this listing its next refresh owes [depth], ahead of the
  /// invalidation that prompts it.
  void owe(CatalogRefresh depth) =>
      ref.read(owedDepthsProvider).owe(self, depth);

  /// The listing for a build: refreshed in place, or read from its head
  /// when nothing is held or [source] is not the last build's.
  ///
  /// [source] is what the listing is read from and is a listing of: the
  /// values of the dependencies its build watches. One that moved makes
  /// this another listing, and nothing read for the one before belongs
  /// in it. Compared here because `Ref.isReload` cannot say: a listing
  /// already invalidated stops hearing its dependencies until it
  /// rebuilds, which is every listing a pushed page covers.
  @protected
  Future<StateT> buildInPlace({required Object? source}) {
    final owed = ref.read(owedDepthsProvider);
    _hearDisposal();
    final moved = source != _source;
    _source = source;
    // A head read already under way is waited for like any other.
    final nothing = _held == null && !_heading;
    if (nothing || moved || ref.isFirstBuild) return _fromHead(owed);
    return _refreshed(owed);
  }

  Future<StateT> _fromHead(OwedDepths owed) async {
    final epoch = ++_epoch;
    _starts++;
    _held = null;
    _paging = false;
    startingOver();
    // The listing whole, whatever was owed.
    owed.take(self);
    _settled();
    _heading = true;
    final pass = _begin();
    try {
      final rows = await _single(
        () => readRows(want: 1, maxPages: walkLimit, stop: () => _stale(epoch)),
      );
      if (!_stale(epoch)) _held = rows;
      return shape(rows, loadingMore: false);
    } finally {
      if (epoch == _epoch) _heading = false;
      _end(pass, landed: epoch == _epoch);
    }
  }

  Future<StateT> _refreshed(OwedDepths owed) async {
    // An invalidation ends riverpod's interest in this build, whatever
    // it goes on to return.
    var live = true;
    ref.onDispose(() => live = false);
    // The build that reads the head is ended by the invalidation this
    // one answers, so its rows are shown from here once they land.
    var unshown = _held == null;
    // A site that names no depth gets the loaded extent, never a reset.
    CatalogRefresh? unnamed = CatalogRefresh.loaded;
    var applied = false;
    var queued = false;
    void queue(bool waiting) {
      if (queued == waiting) return;
      queued = waiting;
      _queued += waiting ? 1 : -1;
    }

    try {
      while (true) {
        queue(true);
        while (_reading != null) {
          await _reading;
        }
        // Ended before its read began: the build that replaces this one
        // reads, now or once the listing is uncovered.
        if (!live) break;
        // The head read it waited for failed, and nobody was listening:
        // this build reads the head, and its failure is a first build's.
        if (_held == null) {
          queue(false);
          return await _fromHead(owed);
        }
        if (unshown) {
          unshown = false;
          _publish();
        }
        final depth = owed.take(self) ?? unnamed;
        unnamed = null;
        if (depth == null) break;
        final timed = _timed;
        _timed = false;
        queue(false);
        final pass = _begin();
        _Honoured? honoured;
        try {
          honoured = await _single(() => _honour(depth, owed));
        } finally {
          // A defect ends the pass too, or what waits on it never would.
          _end(pass, landed: honoured != _Honoured.dropped);
        }
        applied = applied || honoured == _Honoured.applied;
        if (honoured == _Honoured.applied) _settled();
        if (honoured == _Honoured.failed && ref.mounted) {
          ref.read(failedRefreshesProvider).failed(self);
        }
        // An ended build's successor is the next attempt.
        if (honoured == _Honoured.failed && live) _askAgain(timed: timed);
        // Replaced under the read: asked again of the listing that stands.
        if (honoured != _Honoured.dropped) break;
      }
    } finally {
      queue(false);
    }
    // Nobody is listening for what an ended build returns, so the rows
    // it read are shown here rather than after the pass behind it.
    if (applied && !live) _publish();
    // Without rows only once ended, when nothing reads the answer.
    final held = _held ?? (rows: <RowT>[], nextCursor: null);
    return shape(held, loadingMore: _paging);
  }

  Future<_Honoured> _honour(CatalogRefresh depth, OwedDepths owed) async {
    final epoch = _epoch;
    final starts = _starts;
    bool gone() => _stale(epoch);
    void oweBack() {
      if (ref.mounted && starts == _starts) owed.owe(self, depth);
    }

    final held = _held!;
    final extent = math.max(held.rows.length, 1);
    try {
      var fresh = _distinct(await switch (depth) {
        CatalogRefresh.head => readRows(
          want: math.min(extent, 2 * pageRows),
          maxPages: 2,
          stop: gone,
        ),
        CatalogRefresh.loaded => readRows(want: extent, stop: gone),
      });
      if (depth == CatalogRefresh.head && !gone()) {
        final spliced = spliceHead(fresh: fresh, held: held, keyOf: rowKey);
        // An end the listing outgrew is not kept: it would say there is
        // no more, with nothing to page on from. The head stands for
        // the listing instead, read on through the extent held where it
        // stops short of it, as a loaded pass reads it, and ends on a
        // cursor of its own.
        if (!_outgrown(held: held, fresh: fresh, spliced: spliced)) {
          fresh = spliced;
        } else if (fresh.rows.length < extent) {
          final rest = await readRows(
            from: fresh.nextCursor,
            want: extent - fresh.rows.length,
            stop: gone,
          );
          fresh = _distinct((
            rows: <RowT>[...fresh.rows, ...rest.rows],
            nextCursor: rest.nextCursor,
          ));
        }
      }
      if (gone()) {
        oweBack();
        return _Honoured.dropped;
      }
      _held = fresh;
      return _Honoured.applied;
    } on WaxDeckApiException {
      // Kept rather than traded for an error, as a next page that fails
      // is, and nothing is shown. The depth stays owed, and the listing
      // asks again by itself ([_askAgain]): the pass that fails may be
      // the one at the end of a run of hints, which nothing follows.
      oweBack();
      return gone() ? _Honoured.dropped : _Honoured.failed;
    }
  }

  /// Whether [spliced] ends where the listing no longer does: a tail kept
  /// from a list that had ended, under a head that has not and holds a
  /// row the list lacked. A head that shows nothing new leaves no reason
  /// to doubt the end, and a listing long since read whole is not walked
  /// again by every pass.
  bool _outgrown({
    required PagedRows<RowT> held,
    required PagedRows<RowT> fresh,
    required PagedRows<RowT> spliced,
  }) {
    if (spliced.nextCursor != null || fresh.nextCursor == null) return false;
    final had = <Object>{for (final row in held.rows) rowKey(row)};
    return fresh.rows.any((row) => !had.contains(rowKey(row)));
  }

  /// [walk] with each row once. A row whose sort moves it past a page
  /// boundary between two page reads comes back in both, and rows are
  /// keyed.
  PagedRows<RowT> _distinct(PagedRows<RowT> walk) {
    final seen = <Object>{};
    final rows = <RowT>[
      for (final row in walk.rows)
        if (seen.add(rowKey(row))) row,
    ];
    if (rows.length == walk.rows.length) return walk;
    return (rows: rows, nextCursor: walk.nextCursor);
  }

  /// Reads the next page and appends it. Answers whether rows were added.
  /// [started] and [failed] are for what a notifier shows of a page read
  /// beside the rows.
  @protected
  Future<bool> loadMoreInPlace({
    void Function()? started,
    void Function()? failed,
  }) async {
    final entered = _held;
    if (entered == null || entered.nextCursor == null || _paging) return false;
    final epoch = _epoch;
    bool gone() => _stale(epoch);
    _paging = true;
    started?.call();
    _publish();
    try {
      while (_reading != null) {
        await _reading;
        if (gone()) return false;
      }
      final from = _held!.nextCursor;
      // The refresh it waited for read the listing's end.
      if (from == null) return false;
      final page = await _single(
        () => readRows(from: from, want: 1, maxPages: walkLimit, stop: gone),
      );
      if (gone()) return false;
      final held = _held!;
      final have = <Object>{for (final row in held.rows) rowKey(row)};
      final added = <RowT>[
        for (final row in page.rows)
          if (have.add(rowKey(row))) row,
      ];
      _held = (
        rows: <RowT>[...held.rows, ...added],
        nextCursor: page.nextCursor,
      );
      return added.isNotEmpty;
    } on WaxDeckApiException {
      // An expected transport or server error. Keep what is held;
      // scrolling near the end again retries.
      if (!gone()) failed?.call();
      return false;
    } catch (_) {
      // A defect, not a hiccup: it goes on to the app's error handler.
      if (!gone()) failed?.call();
      rethrow;
    } finally {
      // The guard is what keeps two page reads from racing. Left set, it
      // would wedge paging for the listing's life, silently.
      if (!gone()) {
        _paging = false;
        _publish();
      }
    }
  }

  /// Replaces the listing with what [read] answers, ahead of any read in
  /// flight, whose rows are then dropped. A null answer keeps the
  /// listing. [adopt] runs as the rows are taken.
  @protected
  Future<bool> replaceInPlace(
    Future<PagedRows<RowT>?> Function() read, {
    required void Function() adopt,
  }) async {
    if (_held == null) return false;
    final owed = ref.read(owedDepthsProvider);
    final epoch = ++_epoch;
    bool gone() => _stale(epoch);
    // A page read in flight is abandoned, and its guard with it.
    _paging = false;
    // Replaced, not extended, so this reads as a load rather than a next
    // page's trailing ghost.
    state = AsyncLoading<StateT>();
    // A pass, for what waits on one it overtakes: none need follow it.
    final pass = _begin();
    try {
      final rows = await _single(read);
      if (gone()) return false;
      if (rows == null) {
        _publish();
        return false;
      }
      adopt();
      _held = rows;
      // Read whole just now: nothing older is owed.
      owed.take(self);
      _settled();
      _publish();
      return true;
    } on WaxDeckApiException {
      // Keep the listing rather than trade it for an error screen.
      if (!gone()) _publish();
      return false;
    } catch (_) {
      // A defect. Put a usable listing back first, or the screen is a
      // permanent skeleton with no retry on it.
      if (!gone()) _publish();
      rethrow;
    } finally {
      _end(pass, landed: !gone());
    }
  }

  /// Rewrites the rows held, each through [amend]: what the notifier
  /// knows of a row ahead of any read. A refresh that lands after it
  /// brings the server's word for the same rows.
  @protected
  void amendInPlace(RowT Function(RowT row) amend) =>
      rewriteInPlace((rows) => <RowT>[for (final row in rows) amend(row)]);

  /// Replaces the rows held with what [rewrite] makes of them: a row this
  /// notifier wrote or dropped ahead of any read. A refresh that lands
  /// after it brings the server's word for the listing.
  @protected
  void rewriteInPlace(List<RowT> Function(List<RowT> rows) rewrite) {
    final held = _held;
    if (held == null || !ref.mounted) return;
    _held = (rows: rewrite(held.rows), nextCursor: held.nextCursor);
    _publish();
  }

  /// Drops what is held and reads the listing again from its head.
  @protected
  void startOver() {
    _epoch++;
    _starts++;
    _held = null;
    _paging = false;
    _heading = false;
    ref.invalidateSelf();
  }

  /// Runs [read] as the one read in flight.
  Future<T> _single<T>(Future<T> Function() read) async {
    final done = Completer<void>();
    final mine = _reading = done.future;
    try {
      return await read();
    } finally {
      // A listing replaced meanwhile has a read of its own in flight.
      if (identical(_reading, mine)) _reading = null;
      done.complete();
    }
  }

  void _publish() {
    final held = _held;
    if (held == null || !ref.mounted) return;
    state = AsyncData(shape(held, loadingMore: _paging));
  }
}
