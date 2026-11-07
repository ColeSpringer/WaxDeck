import '../models.dart';

/// Server liveness and version.
abstract interface class SystemApi {
  /// `GET /health`: liveness and version probe.
  Future<ServerHealth> health();
}
