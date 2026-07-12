/// Plain-Dart views over the generated built_value DTOs.
///
/// These are the types feature code sees. They are deliberately boring:
/// no built_value, no generator idioms, easy to construct in tests.
library;

/// Server liveness/version snapshot (`GET /health`).
class ServerHealth {
  const ServerHealth({
    required this.status,
    required this.version,
    required this.apiVersion,
  });

  final String status;
  final String version;
  final int apiVersion;

  bool get ok => status == 'ok';
}

/// Structured API error (the spec's `Error` schema), thrown by the client.
class WaxDeckApiException implements Exception {
  const WaxDeckApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  /// Stable machine-readable code (`unauthenticated`, `not-found`, and so on).
  final String code;

  /// Human-readable explanation; not stable, never parse it.
  final String message;

  final int? statusCode;

  @override
  String toString() => 'WaxDeckApiException($code, $statusCode): $message';
}
