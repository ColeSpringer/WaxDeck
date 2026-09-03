import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'file_picker_impl.dart' as impl;

/// Audio extensions the pickers offer and the drop areas accept
/// (lowercase, no dot): the fallback mirror of the server's default
/// accepted-format set (uploadFormatSet in
/// server/internal/service/uploads.go - keep in step). The health
/// payload reports the effective set, which is what actually filters
/// once read; this mirror covers servers older than the field and the
/// moment before the read lands. Native dialogs keep an "All files"
/// group so anything the filter missed stays reachable; the server's
/// session create is the real gate.
const kAcceptedAudioExtensions = {
  'mp3', 'mpga', 'flac', 'wav', 'wave', 'ogg', 'oga', 'opus', //
  'm4a', 'm4b', 'm4r', 'mp4', 'alac', 'aac', 'adts', 'wma', //
  'aiff', 'aif', 'aifc', 'afc', 'ape', 'wv', 'mpc', 'mp+', 'mka',
};

/// Extensions the server refuses outright rather than merely not
/// accepting: the fallback mirror of its DRM deny-list (drmFormats in
/// server/internal/service/uploads.go - keep in step), served by the
/// health payload the same way. The folder walk counts these apart
/// from the rest of what its filter drops, so the skip report can say
/// the files can never play instead of lumping an encrypted audiobook
/// in with cover images.
const kRejectedAudioExtensions = {'aax', 'aaxc'};

/// The extension sets one pick or drop filters against: what uploads
/// accept, and the deny-list counted apart as "can never play". The
/// default is the hardcoded mirrors; audio surfaces pass the
/// server-reported sets where a health read supplied them.
class UploadFormatSets {
  const UploadFormatSets({
    this.accepted = kAcceptedAudioExtensions,
    this.rejected = kRejectedAudioExtensions,
  });

  /// A non-audio zone (artwork, archives): its own accepted set, no
  /// deny-list - nothing there is "DRM audio", it is just not taken.
  const UploadFormatSets.only(Set<String> accepted)
    : this(accepted: accepted, rejected: const {});

  final Set<String> accepted;
  final Set<String> rejected;

  /// Whether a walk keeps [name]: in the accepted set and not on the
  /// deny-list - which wins, as it does at the server's gate, so a set
  /// that somehow lists a DRM extension still counts those files as
  /// "can never play" instead of admitting them to be refused one by
  /// one.
  bool accepts(String name) =>
      !refuses(name) && hasAcceptedExtension(name, accepted);

  /// Whether [name] is on the DRM deny-list.
  bool refuses(String name) => hasAcceptedExtension(name, rejected);
}

/// Whether the file name's extension is in the given set
/// (case-insensitive; extensionless names never match).
bool hasAcceptedExtension(String name, Set<String> extensions) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return false;
  return extensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Assembles one [FolderPick] the way every walk assembles it: [keep]
/// filters and tallies, [build] orders and packs - so the
/// DRM-vs-unsupported split and the stable ordering live once rather
/// than once per platform.
class FolderPickBuilder {
  FolderPickBuilder(this.formats);

  final UploadFormatSets formats;
  final files = <PickedAudioFile>[];
  var _skippedUnsupported = 0;
  var _skippedDrm = 0;

  /// Whether [name] passes the filter; counted into its bucket when
  /// not.
  bool keep(String name) {
    if (formats.refuses(name)) {
      _skippedDrm++;
      return false;
    }
    if (!hasAcceptedExtension(name, formats.accepted)) {
      _skippedUnsupported++;
      return false;
    }
    return true;
  }

  /// Counts a file the walk could not make uploadable (a provider
  /// reporting no size); dropping it silently would leave the whole
  /// pick looking like it did nothing.
  void skipUnreadable() => _skippedUnsupported++;

  /// Folds a nested walk's pick in (a dropped directory expanding).
  void merge(FolderPick pick) {
    files.addAll(pick.files);
    _skippedUnsupported += pick.skippedUnsupported;
    _skippedDrm += pick.skippedDrm;
  }

  /// The pick, files in stable (relativeDir, name) order so transfers
  /// and tests stay deterministic whatever order the platform listed.
  FolderPick build() {
    files.sort((a, b) {
      final byDir = a.relativeDir.compareTo(b.relativeDir);
      return byDir != 0 ? byDir : a.name.compareTo(b.name);
    });
    return FolderPick(
      files: files,
      skippedUnsupported: _skippedUnsupported,
      skippedDrm: _skippedDrm,
    );
  }
}

/// Joins a picked folder's own name to a path relative to it, which is
/// the `relativeDir` shape every platform's walk reports. Shared,
/// because the walks compose it from different halves - the desktop one
/// from a filesystem path, the Android one from a tree-relative
/// directory and the granted root - and they have to agree.
String joinRelativeDir(String root, String relative) {
  if (root.isEmpty) return relative;
  if (relative.isEmpty) return root;
  return '$root/$relative';
}

/// One folder pick: the audio that survived the extension filter, plus
/// counts of what the filter dropped. Split, because the two halves
/// mean different things to the person who picked the folder - a cover
/// image was never going to upload, an Audible file looks like audio
/// and can never play - and the report words them apart.
class FolderPick {
  const FolderPick({
    this.files = const [],
    this.skippedUnsupported = 0,
    this.skippedDrm = 0,
  });

  final List<PickedAudioFile> files;

  /// Files outside the accepted set, [skippedDrm] not included.
  final int skippedUnsupported;

  /// Files on the DRM deny-list ([UploadFormatSets.rejected]).
  final int skippedDrm;
}

/// One picked or dropped file as a lazy reference: the transfer pulls
/// bytes in windows when it needs them, so a multi-hundred-megabyte
/// album never sits whole in memory. Native picks carry [path] and
/// stream from disk; web picks carry [openRead] over the browser's
/// file handle.
class PickedAudioFile {
  const PickedAudioFile({
    required this.name,
    required this.size,
    this.relativeDir = '',
    this.path,
    this.openRead,
  });

  /// Bare file name.
  final String name;

  /// Size in bytes, known up front for the session declaration.
  final int size;

  /// Directory relative to the picked or dropped folder, forward-slash
  /// separated; empty for a file at the top. Carried to the server as
  /// the batch's clustering hint (`batchPath`).
  final String relativeDir;

  /// Local filesystem path, set for native picks and drops.
  final String? path;

  /// Windowed byte-stream accessor reading `[start, end)` lazily; set
  /// for web picks and drops (and usable everywhere it is set).
  final Stream<List<int>> Function([int? start, int? end])? openRead;
}

/// Platform file picking behind a WaxDeck-owned interface, so screens
/// never touch a picker plugin directly.
abstract interface class FilePickerPort {
  /// Opens the platform picker; empty when the user cancels.
  /// [audioLabel] and [anyLabel] name the dialog's two filter rows, and
  /// [formats] carries the sets the dialog filters to: a port is built
  /// off the tree and has neither a table to word rows from nor a ref
  /// to read the server's sets through.
  Future<List<PickedAudioFile>> pickAudioFiles({
    required String audioLabel,
    required String anyLabel,
    required UploadFormatSets formats,
  });

  /// Whether [pickAudioFolder] works here: Linux, Windows, web, and
  /// Android (SAF tree access) - which is every platform WaxDeck
  /// builds for today, so the answer only goes false on a platform the
  /// app has not been ported to.
  bool get canPickFolders;

  /// Picks a folder and returns its audio files recursively, with
  /// [PickedAudioFile.relativeDir] carrying the in-folder hierarchy
  /// rooted at the folder's own name, plus what [formats]'s filter
  /// dropped; empty when the user cancels.
  Future<FolderPick> pickAudioFolder({required UploadFormatSets formats});

  /// Picks one arbitrary file filtered to [extensions] (the backup
  /// archive case); null when the user cancels. [label] and [anyLabel]
  /// name the dialog's two filter rows, as in [pickAudioFiles].
  Future<PickedAudioFile?> pickFile({
    required Set<String> extensions,
    required String label,
    required String anyLabel,
  });
}

/// The platform port. Null on platforms with no picker wiring - and in
/// widget tests overriding it so - which hides every pick affordance;
/// that hide-when-null contract predates the real implementations and
/// stands.
final filePickerProvider = Provider<FilePickerPort?>(
  (ref) => impl.createFilePickerPort(),
);
