import '../models.dart';

/// Listening statistics and year in review.
abstract interface class StatsApi {
  /// `GET /stats/listening`: the caller's aggregated listening time.
  /// [range] is `7d`, `30d`, `90d`, `365d`, or `all`; [bucket] is
  /// `day`, `week`, or `month`. Absent values ride the server
  /// defaults (`30d`, `day`).
  Future<ListeningStats> getListeningStats({String? range, String? bucket});

  /// `GET /stats/heatmap`: the caller's per-day listening for one
  /// calendar [year] (default: the current year), plus streaks.
  Future<ListeningHeatmap> getListeningHeatmap({int? year});

  /// `GET /stats/top`: one ranked top list. [kind] is `artists`,
  /// `albums`, `genres`, or `shows`; [range] as in
  /// [getListeningStats].
  Future<TopList> getTopList({required String kind, String? range, int? limit});

  /// `GET /stats/sessions`: the caller's keyset-paginated listen log,
  /// newest first, optionally filtered to one reporting [client].
  Future<ListenLogPage> listListenLog({
    String? client,
    String? cursor,
    int? limit,
  });

  /// `GET /stats/year-in-review`: the caller's listening recap for one
  /// calendar [year] (default: the current year).
  Future<YearInReview> getYearInReview({int? year});

  /// `GET /stats/server-year-in-review`: the whole server's recap for
  /// one calendar [year], aggregated across users who have not opted
  /// out of shared stats.
  Future<ServerYearInReview> getServerYearInReview({int? year});
}
