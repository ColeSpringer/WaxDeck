/// Where a rendered share card goes once it exists: a browser download,
/// a file on a desktop, the share sheet on Android. A WaxDeck-owned
/// port with no plugin behind it.
library;

export 'share_card_export_stub.dart'
    if (dart.library.io) 'share_card_export_io.dart'
    if (dart.library.js_interop) 'share_card_export_web.dart'
    show createShareCardExporter;

/// What became of a card.
sealed class ShareCardOutcome {
  const ShareCardOutcome();
}

/// Handed to the platform's share sheet. Where it went is not ours.
class ShareCardShared extends ShareCardOutcome {
  const ShareCardShared();
}

/// Written somewhere the person can find it.
class ShareCardSaved extends ShareCardOutcome {
  const ShareCardSaved(this.where);

  /// A path on a desktop, a file name in the browser's downloads.
  final String where;
}

/// Nothing happened, and why. A [kind] rather than a sentence: an
/// exporter is built outside the element tree and has no table, so the
/// screen words it. [detail] is the platform's own account, if any.
class ShareCardFailed extends ShareCardOutcome {
  const ShareCardFailed(this.kind, {this.detail});

  final ShareCardFailure kind;

  final String? detail;
}

/// Why a card did not get out.
enum ShareCardFailure {
  /// The share sheet took it and declined, saying nothing usable.
  shareRefused,

  /// The platform side of the share channel is older than this Dart
  /// side and has no image support.
  shareUnsupported,

  /// This build cannot keep an image at all.
  saveUnsupported,

  /// Neither a downloads folder nor a documents folder to write into.
  noDestination,

  /// The write itself failed, and [ShareCardFailed.detail] says how.
  writeFailed,
}

/// Getting a finished card off this device.
abstract interface class ShareCardExporter {
  /// Whether this build can export at all. False hides the action
  /// rather than offering one that fails.
  bool get canExport;

  /// Hands over [png] under [fileName] (with its extension), described
  /// to the share sheet by [subject] where a platform shows one.
  Future<ShareCardOutcome> export({
    required List<int> png,
    required String fileName,
    required String subject,
  });
}

/// The port for a platform that cannot keep an image at all.
class InertShareCardExporter implements ShareCardExporter {
  const InertShareCardExporter();

  @override
  bool get canExport => false;

  @override
  Future<ShareCardOutcome> export({
    required List<int> png,
    required String fileName,
    required String subject,
  }) async => const ShareCardFailed(ShareCardFailure.saveUnsupported);
}
