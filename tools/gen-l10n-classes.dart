// Runs gen-l10n for each package named, writing only the classes whose
// bytes changed.
//
// gen-l10n rewrites every class on each run, and the web build's
// staleness check (the Makefile's WEB_INPUTS) reads their mtimes, so a
// run that changed nothing would still rebuild the web bundle. It runs
// here on a staging copy of the package under its .dart_tool - the
// l10n.yaml, the pubspec and the ARB directory - and each class it writes
// there replaces the package's own only where the bytes differ. The copy
// keeps the package's relative paths, which the generated classes name.
//
//   dart run tools/gen-l10n-classes.dart <package>...   (via `make generate`)
//
// Uses only dart: libraries, so it runs without a package resolution.
import 'dart:io';

import 'src/output_file.dart';

/// What the run stops on: thrown rather than exited on, so a stage's
/// cleanup runs on the way out.
class _Failure implements Exception {
  _Failure(this.message);

  final String message;
}

Never _fail(String message) => throw _Failure(message);

void main(List<String> packages) {
  try {
    if (packages.isEmpty) _fail('name the packages to generate for');
    packages.forEach(_generate);
  } on _Failure catch (failure) {
    stderr.writeln('gen-l10n-classes: ${failure.message}');
    exit(1);
  }
}

void _generate(String package) {
  final config = File('$package/l10n.yaml');
  if (!config.existsSync()) _fail('$package has no l10n.yaml');
  final arbDir = _option(config, 'arb-dir');
  final outDir = _option(config, 'output-dir');
  final stage = Directory('$package/.dart_tool/gen-l10n-classes');
  if (stage.existsSync()) stage.deleteSync(recursive: true);
  try {
    Directory('${stage.path}/$arbDir').createSync(recursive: true);
    config.copySync('${stage.path}/l10n.yaml');
    File('$package/pubspec.yaml').copySync('${stage.path}/pubspec.yaml');
    final arbs = Directory('$package/$arbDir').listSync().whereType<File>();
    for (final arb in arbs) {
      arb.copySync('${stage.path}/$arbDir/${arb.uri.pathSegments.last}');
    }
    final result = Process.runSync(
      'flutter',
      ['gen-l10n'],
      workingDirectory: stage.path,
      runInShell: Platform.isWindows,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) _fail('gen-l10n failed for $package');
    Directory('$package/$outDir').createSync(recursive: true);
    final generated = Directory('${stage.path}/$outDir').listSync();
    for (final file in generated.whereType<File>()) {
      final name = file.uri.pathSegments.last;
      writeIfChanged('$package/$outDir/$name', file.readAsStringSync());
    }
  } finally {
    if (stage.existsSync()) stage.deleteSync(recursive: true);
  }
}

/// The value l10n.yaml gives the top-level [key], read as a plain scalar
/// with any comment after it.
String _option(File config, String key) {
  for (final line in config.readAsLinesSync()) {
    if (line.startsWith('$key:')) {
      final value = line.substring(key.length + 1).split(' #').first.trim();
      if (value.isNotEmpty) return value;
    }
  }
  _fail('${config.path} sets no $key');
}
