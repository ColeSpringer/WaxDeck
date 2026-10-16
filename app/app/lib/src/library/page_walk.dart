import 'package:waxdeck_api/waxdeck_api.dart';

/// How many pages a walk asking a question reads before it answers
/// "cannot say".
const int kProbePageBudget = 6;

/// How wide a page a probe reads once a page has come back showing
/// nothing. Wider than a row: a row is the worst case for a listing that
/// drops rows after the cut, where one dropped item leaves the page
/// saying nothing at all.
const int kProbePageSize = 50;

/// What a walk read: the items, and where the listing stands.
class PageWalk {
  const PageWalk({required this.items, this.nextCursor});

  /// Every item the pages read held, in listing order, possibly more
  /// than the walk wanted.
  final List<ItemSummary> items;

  /// The cursor to read on from; null once the last page was read.
  final String? nextCursor;

  /// Whether the walk reached the end of the listing.
  bool get exhausted => nextCursor == null;

  /// Whether the walk proved the listing holds nothing: read to its end
  /// with nothing in hand. A walk that stopped before the end may have
  /// stopped short of anything.
  bool get provedEmpty => items.isEmpty && exhausted;
}

/// Reads pages until [want] items are in hand, the listing ends, or
/// [maxPages] were read, for a question: a walk that runs out answers
/// "cannot say". Starts at [from], the head of the listing when null.
///
/// One page is not the answer to "is there anything": the listing
/// contract allows a page that comes back short, even empty, and still
/// carries a cursor, and the server drops after the cut the rows the
/// caller's content settings refuse. Only a page without a cursor ends
/// the listing.
///
/// [stop] is asked after each page, and true ends the walk with what it
/// holds: the reader is gone. With [keepOnFailure], a page that fails
/// once rows are in hand ends the walk with them, its cursor the failed
/// page's, rather than throwing them away; a failure with nothing in
/// hand is thrown either way.
Future<PageWalk> walkPages(
  Future<ItemPage> Function(String? cursor) fetch, {
  int want = 1,
  int maxPages = kProbePageBudget,
  String? from,
  bool Function()? stop,
  bool keepOnFailure = false,
}) => _walk(
  fetch,
  want: want,
  maxPages: maxPages,
  from: from,
  stop: stop,
  keepOnFailure: keepOnFailure,
);

/// [walkPages] with no page budget, for a listing that draws what it
/// finds: there a walk that ran out would leave a list standing short
/// over rows it never reached.
Future<PageWalk> readPages(
  Future<ItemPage> Function(String? cursor) fetch, {
  required int want,
  String? from,
  bool Function()? stop,
  bool keepOnFailure = false,
}) => _walk(
  fetch,
  want: want,
  maxPages: null,
  from: from,
  stop: stop,
  keepOnFailure: keepOnFailure,
);

/// Asks a listing whether it holds anything: one row first, which
/// answers whenever the listing shows it, then pages of [kProbePageSize]
/// past one that showed nothing, within [kProbePageBudget].
Future<PageWalk> probePages(
  Future<ItemPage> Function(String? cursor, int limit) fetch,
) => walkPages((cursor) => fetch(cursor, cursor == null ? 1 : kProbePageSize));

Future<PageWalk> _walk(
  Future<ItemPage> Function(String? cursor) fetch, {
  required int want,
  required int? maxPages,
  required String? from,
  required bool Function()? stop,
  required bool keepOnFailure,
}) async {
  assert(
    want > 0 && (maxPages == null || maxPages > 0),
    'a walk that reads nothing proves nothing',
  );
  final items = <ItemSummary>[];
  var cursor = from;
  for (var read = 0; maxPages == null || read < maxPages; read++) {
    final ItemPage page;
    try {
      page = await fetch(cursor);
    } on WaxDeckApiException {
      if (!keepOnFailure || items.isEmpty) rethrow;
      break;
    }
    items.addAll(page.items);
    cursor = page.nextCursor;
    if (cursor == null || items.length >= want) break;
    if (stop?.call() ?? false) break;
  }
  return PageWalk(items: items, nextCursor: cursor);
}
