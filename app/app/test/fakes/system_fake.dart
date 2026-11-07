import 'package:waxdeck_api/waxdeck_api.dart';

import 'state.dart';

/// In-memory [SystemApi] for `FakeRepository`.
mixin FakeSystem on FakeRepositoryState implements SystemApi {
  /// What the health probe reports. Mutable so a test can restart the
  /// server under a running client, which is what the shell's
  /// server-updated banner watches for.
  String serverVersion = 'test';
  int apiVersion = 1;

  /// What [health] reports as the server's upload-format sets. Null is
  /// a server older than the fields, which is what most tests want:
  /// pickers then fall back to the hardcoded mirror.
  List<String>? serverUploadFormats;
  List<String>? serverRejectedFormats;

  /// What [health] reports of the streaming engine and of podcasts. Null
  /// is a server older than the fields, which reads as an engine with
  /// nothing to say and podcasts on.
  ServerStreaming? serverStreaming;
  bool? serverPodcasts;

  /// Thrown by [health] when set. Deliberately an [Object] rather than
  /// the structured API error: the client maps only transport failures
  /// into that type, and a response a generated deserializer cannot
  /// build throws something else entirely - which is the shape a probe
  /// meets right after the server it is probing was replaced.
  Object? serverHealthError;

  @override
  Future<ServerHealth> health() async {
    final failure = serverHealthError;
    if (failure != null) throw failure;
    return ServerHealth(
      status: 'ok',
      version: serverVersion,
      apiVersion: apiVersion,
      uploadFormats: serverUploadFormats,
      rejectedFormats: serverRejectedFormats,
      streaming: serverStreaming,
      podcasts: serverPodcasts,
    );
  }
}
