import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';

/// One series and the books in it.
///
/// `autoDispose` and a family, like the album header's read: the screen
/// is the only thing that wants it, and holding every series a listener
/// passed through would be a cache nothing invalidates. A 404 is final,
/// so it does not spend the ten-attempt backoff.
final bookSeriesDetailProvider = FutureProvider.autoDispose
    .family<BookSeriesDetail, String>(
      (ref, pid) => ref.watch(repositoryProvider).getBookSeries(pid),
      retry: retryUnlessRefused,
    );
