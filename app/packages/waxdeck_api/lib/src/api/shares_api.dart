import '../models.dart';

/// Public share links.
abstract interface class SharesApi {
  /// `GET /shares`: the caller's share links, newest first. [all] lists
  /// every account's links instead, which the server allows only to an
  /// administrator and which is the only listing that names owners.
  Future<SharePage> listShares({String? cursor, int? limit, bool all});

  /// `POST /shares`: mints a public share link for a track, playlist,
  /// book, or episode [pid]. [expiresInHours] bounds its lifetime
  /// (absent: never expires); [positionMs] is the episode
  /// copy-link-at-timestamp start.
  Future<Share> createShare({
    required String pid,
    int? expiresInHours,
    bool allowDownload,
    int? positionMs,
  });

  /// `DELETE /shares/{shareId}`: revokes a share link.
  Future<void> revokeShare(String shareId);
}
