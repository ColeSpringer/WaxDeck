/// The server answered a WebSocket upgrade with [status] instead of
/// switching protocols: a word about the request, unlike a link that never
/// reached anyone. Only a native connector can read it; a browser reports
/// every refused upgrade like a dead network.
class UpgradeRefused implements Exception {
  const UpgradeRefused(this.status);

  final int status;

  @override
  String toString() => 'UpgradeRefused: the server answered $status';
}
