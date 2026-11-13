/// The analyzer's resolved view of this package, for the audits that ask
/// questions of `lib/` by element rather than by text.
///
/// `lib_audit_test.dart` opens one host in `setUpAll` and every audit
/// shares it, since the first resolution links the element model of every
/// dependency. Fixtures are libraries laid over the package in memory at
/// paths under it, so their `package:` imports resolve against the real
/// dependencies and nothing is written to disk.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/overlay_file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:path/path.dart' as p;

class AnalysisHost {
  AnalysisHost._(this.root, this._overlay, this._collection);

  /// A host over the app package, which must be the working directory, as
  /// it is under `flutter test`.
  factory AnalysisHost() {
    final root = p.normalize(Directory.current.absolute.path);
    if (!File(p.join(root, 'lib', 'src', 'providers.dart')).existsSync()) {
      throw StateError('AnalysisHost runs from the app package, not $root');
    }
    final overlay = OverlayResourceProvider(PhysicalResourceProvider.INSTANCE);
    return AnalysisHost._(
      root,
      overlay,
      AnalysisContextCollection(
        includedPaths: [root],
        resourceProvider: overlay,
        sdkPath: _sdkPath(),
      ),
    );
  }

  /// The package's absolute path.
  final String root;

  final OverlayResourceProvider _overlay;
  final AnalysisContextCollection _collection;
  final _resolved = <String, Future<ResolvedLibraryResult>>{};
  var _stamp = 0;

  /// The analysis of the package, fixtures included.
  AnalysisSession get session =>
      _collection.contextFor(absolute('lib/src/providers.dart')).currentSession;

  /// The absolute path of [relative], a forward-slash path in the package.
  String absolute(String relative) => p.joinAll([root, ...relative.split('/')]);

  /// [path], absolute, as a forward-slash path in the package.
  String relative(String path) =>
      p.split(p.relative(path, from: root)).join('/');

  /// Lays [content] over the package at [relative], a path nothing exists
  /// at or has read yet, so the session needs no word of a change.
  void write(String relative, String content) {
    final path = absolute(relative);
    if (_overlay.hasOverlay(path) || File(path).existsSync()) {
      throw StateError('$relative is taken; a fixture needs a fresh path');
    }
    _overlay.setOverlay(path, content: content, modificationStamp: _stamp++);
  }

  /// The library whose defining unit is at [path], absolute, resolved once
  /// for every audit that asks.
  Future<ResolvedLibraryResult> resolve(String path) =>
      _resolved[path] ??= () async {
        final result = await session.getResolvedLibrary(path);
        if (result is! ResolvedLibraryResult) {
          throw StateError('cannot resolve ${relative(path)}: $result');
        }
        return result;
      }();

  /// One line for each unit of [library] under `lib/` with an error, naming
  /// the first: code that does not compile resolves to less than it says.
  List<String> errors(ResolvedLibraryResult library) => [
    for (final unit in library.units)
      if (relative(unit.path) case final path when path.startsWith('lib/'))
        if (_firstError(unit) case final error?)
          '$path:${unit.lineInfo.getLocation(error.offset).lineNumber}: '
              '${error.problemMessage.messageText(includeUrl: false)} (an '
              'audit cannot read code that does not compile)',
  ];

  Future<void> dispose() => _collection.dispose();
}

/// The Dart files under `lib/` on disk, as forward-slash package paths.
List<String> libFiles(AnalysisHost host) => [
  for (final file in Directory(host.absolute('lib')).listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart')) host.relative(file.path),
]..sort();

Diagnostic? _firstError(ResolvedUnitResult unit) {
  Diagnostic? first;
  for (final diagnostic in unit.diagnostics) {
    if (diagnostic.severity == Severity.error &&
        (first == null || diagnostic.offset < first.offset)) {
      first = diagnostic;
    }
  }
  return first;
}

/// The Dart SDK to resolve against. Under `flutter test` the executable is
/// the test runner, so the SDK is Flutter's own; under `dart` it is the
/// running one.
String _sdkPath() {
  final flutter = Platform.environment['FLUTTER_ROOT'];
  final candidates = [
    if (flutter != null) p.join(flutter, 'bin', 'cache', 'dart-sdk'),
    p.dirname(p.dirname(Platform.resolvedExecutable)),
  ];
  for (final sdk in candidates) {
    if (File(p.join(sdk, 'version')).existsSync() &&
        Directory(p.join(sdk, 'lib', '_internal')).existsSync()) {
      return p.normalize(sdk);
    }
  }
  throw StateError(
    'No Dart SDK found: tried ${candidates.join(', ')}. Run under '
    '`flutter test`, which sets FLUTTER_ROOT, or a `dart` from an SDK.',
  );
}
