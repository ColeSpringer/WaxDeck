import 'dart:async';
import 'dart:math' as math;

import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [SharesApi] for `FakeRepository`.
mixin FakeShares on FakeRepositoryState implements SharesApi {
  /// Thrown by the share endpoints when set.
  WaxDeckApiException? shareError;

  /// Share links, newest first; create and revoke mutate it.
  final List<Share> shares = [];
  int _shareSeq = 0;

  final List<
    ({String pid, int? expiresInHours, bool allowDownload, int? positionMs})
  >
  createShareCalls = [];
  final List<String> revokeShareCalls = [];

  /// Held open, [createShare] waits on it before answering.
  Completer<void>? createShareGate;

  /// Share links every account holds, answered to an `all: true` listing.
  /// Separate from [shares] so a test can prove which listing a screen
  /// asked for.
  final List<Share> allShares = [];

  /// Whether each `listShares` call passed `all`.
  final List<bool> listSharesCalls = [];

  /// The cursor each `listShares` call carried, in call order.
  final List<String?> listSharesCursors = [];

  @override
  Future<SharePage> listShares({
    String? cursor,
    int? limit,
    bool all = false,
  }) async {
    listSharesCalls.add(all);
    listSharesCursors.add(cursor);
    final error = shareError;
    if (error != null) throw error;
    final rows = all ? allShares : shares;
    final from = cursor == null ? 0 : int.parse(cursor);
    final to = limit == null
        ? rows.length
        : math.min(rows.length, from + limit);
    return SharePage(
      shares: rows.sublist(from, to),
      nextCursor: to < rows.length ? '$to' : null,
    );
  }

  @override
  Future<Share> createShare({
    required String pid,
    int? expiresInHours,
    bool allowDownload = false,
    int? positionMs,
  }) async {
    createShareCalls.add((
      pid: pid,
      expiresInHours: expiresInHours,
      allowDownload: allowDownload,
      positionMs: positionMs,
    ));
    await createShareGate?.future;
    final error = shareError;
    if (error != null) throw error;
    final seq = _shareSeq++;
    final createdAt = DateTime.utc(2026, 7, 20, 12);
    final target = libraryItems.where((i) => i.pid == pid).firstOrNull;
    final share = Share(
      pid: 'sh-FAKE$seq',
      url: '/s/FAKESECRET$seq',
      targetPid: pid,
      targetKind: pid.startsWith('pl-')
          ? 'playlist'
          : pid.startsWith('bk-')
          ? 'book'
          : pid.startsWith('ep-')
          ? 'episode'
          : 'track',
      targetTitle: target?.title ?? 'Shared item',
      allowDownload: allowDownload,
      positionMs: positionMs,
      createdAt: createdAt,
      expiresAt: expiresInHours == null
          ? null
          : createdAt.add(Duration(hours: expiresInHours)),
      plays: 0,
    );
    shares.insert(0, share);
    return share;
  }

  @override
  Future<void> revokeShare(String shareId) async {
    final error = shareError;
    if (error != null) throw error;
    revokeShareCalls.add(shareId);
    shares.removeWhere((s) => s.pid == shareId);
  }
}
