import 'dart:async';

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [StatsApi] for `FakeRepository`.
mixin FakeStats on FakeRepositoryState implements StatsApi {
  /// Thrown by the stats endpoints when set.
  WaxDeckApiException? statsError;

  /// Held open, every stats aggregate waits on it, so a test can watch
  /// what a range change draws while the next one is genuinely in
  /// flight.
  Completer<void>? statsGate;

  /// Canned aggregates served by the stats endpoints.
  ListeningStats listeningStats = const ListeningStats(
    range: '30d',
    bucket: 'day',
    timezone: 'UTC',
    totalMs: 0,
    sessions: 0,
    timeSavedMs: 0,
  );
  ListeningHeatmap heatmap = const ListeningHeatmap(
    year: 2026,
    timezone: 'UTC',
    currentStreakDays: 0,
    longestStreakDays: 0,
  );

  /// Top lists by kind; unset kinds answer an empty list.
  final Map<String, TopList> topLists = {};

  /// Listen log entries, newest first, paged like the other lists.
  List<ListenLogEntry> listenLog = [];

  /// Year-in-review recaps; null answers an all-zero recap for the
  /// requested year.
  YearInReview? yearInReview;
  ServerYearInReview? serverYearInReview;

  final List<({String? range, String? bucket})> listeningStatsCalls = [];
  final List<int?> heatmapCalls = [];
  final List<({String kind, String? range, int? limit})> topListCalls = [];
  final List<({String? client, String? cursor, int? limit})> listenLogCalls =
      [];
  final List<int?> yearInReviewCalls = [];
  final List<int?> serverYearInReviewCalls = [];

  @override
  Future<ListeningStats> getListeningStats({
    String? range,
    String? bucket,
  }) async {
    listeningStatsCalls.add((range: range, bucket: bucket));
    await statsGate?.future;
    final error = statsError;
    if (error != null) throw error;
    return listeningStats;
  }

  @override
  Future<ListeningHeatmap> getListeningHeatmap({int? year}) async {
    heatmapCalls.add(year);
    await statsGate?.future;
    final error = statsError;
    if (error != null) throw error;
    return heatmap;
  }

  @override
  Future<TopList> getTopList({
    required String kind,
    String? range,
    int? limit,
  }) async {
    topListCalls.add((kind: kind, range: range, limit: limit));
    await statsGate?.future;
    final error = statsError;
    if (error != null) throw error;
    return topLists[kind] ?? TopList(kind: kind, range: range ?? '30d');
  }

  @override
  Future<ListenLogPage> listListenLog({
    String? client,
    String? cursor,
    int? limit,
  }) async {
    listenLogCalls.add((client: client, cursor: cursor, limit: limit));
    final error = statsError;
    if (error != null) throw error;
    final filtered = client == null
        ? listenLog
        : listenLog.where((e) => e.client == client).toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final pageSize = limit ?? 50;
    final end = (start + pageSize).clamp(0, filtered.length);
    return ListenLogPage(
      sessions: filtered.sublist(start.clamp(0, filtered.length), end),
      nextCursor: end < filtered.length ? '$end' : null,
    );
  }

  @override
  Future<YearInReview> getYearInReview({int? year}) async {
    yearInReviewCalls.add(year);
    final error = statsError;
    if (error != null) throw error;
    return yearInReview ??
        YearInReview(
          year: year ?? 2026,
          timezone: 'UTC',
          totalMs: 0,
          sessions: 0,
          distinctItems: 0,
          newInLibrary: 0,
          timeSavedMs: 0,
          longestStreakDays: 0,
          byMonth: [
            for (var month = 1; month <= 12; month++)
              MonthListening(month: month, ms: 0, sessions: 0),
          ],
        );
  }

  @override
  Future<ServerYearInReview> getServerYearInReview({int? year}) async {
    serverYearInReviewCalls.add(year);
    final error = statsError;
    if (error != null) throw error;
    return serverYearInReview ??
        ServerYearInReview(
          year: year ?? 2026,
          participants: 0,
          totalMs: 0,
          sessions: 0,
        );
  }
}
