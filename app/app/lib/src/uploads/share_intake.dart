/// Platform share-sheet intake behind a WaxDeck-owned port, so widget
/// code never touches platform channels. Android is the only platform
/// with a share sheet handing us intents; everywhere else the port is
/// inert.
library;

export 'share_intake_stub.dart'
    if (dart.library.io) 'share_intake_io.dart'
    show createShareIntakePort;

/// One file handed over by the platform share sheet, already copied to
/// app-private storage by the platform side.
class SharedFile {
  const SharedFile({required this.path, required this.name});

  final String path;

  /// The display name the sharing app reported, used as the upload's
  /// file name.
  final String name;
}

/// One payload from the share sheet: a URL or audio files.
sealed class SharedIntake {
  const SharedIntake();
}

class SharedUrlIntake extends SharedIntake {
  const SharedUrlIntake(this.url);

  final String url;
}

class SharedFilesIntake extends SharedIntake {
  const SharedFilesIntake(this.files);

  final List<SharedFile> files;
}

/// The share-sheet port. [consumeShared] returns-and-clears whatever
/// the platform queued, null when nothing waits; callers poll it on
/// app start and resume.
abstract interface class ShareIntakePort {
  Future<SharedIntake?> consumeShared();
}

/// The do-nothing port for platforms without share-sheet intake.
class InertShareIntakePort implements ShareIntakePort {
  const InertShareIntakePort();

  @override
  Future<SharedIntake?> consumeShared() async => null;
}
