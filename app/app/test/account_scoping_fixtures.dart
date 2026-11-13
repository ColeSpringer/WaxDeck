/// What the scan's fixture cases share: the host over the package, and
/// fixture libraries laid over it in memory.
library;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'account_scoping_scan.dart';
import 'analysis_host.dart';

/// What every fixture library but a part imports.
const _imports = '''
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/providers.dart';
''';

/// The read every fixture makes of the repository.
const read = 'ref.watch(repositoryProvider).getRuleFields()';

/// The watch that keys a provider.
const watch = 'ref.watch(signedInAccountProvider)';

class ScanFixtures {
  /// Fixtures over the host [_host] returns, once the run has opened it.
  ScanFixtures(this._host);

  final AnalysisHost Function() _host;
  var _count = 0;

  /// The breach lines for [files], each a library (or a part) by its path
  /// in a fresh directory under `lib/`, or in [dir], with that directory
  /// cut from the lines. Each must compile, unless [compiles] is false.
  Future<List<String>> scan(
    Map<String, String> files, {
    Set<String> exempt = const {},
    String? dir,
    bool compiles = true,
  }) async {
    final host = _host();
    final at = dir ?? 'lib/scan_fixture${_count++}';
    final paths = <String>[];
    for (final MapEntry(key: name, value: source) in files.entries) {
      final path = '$at/$name';
      host.write(
        path,
        source.trimLeft().startsWith('part of') ? source : '$_imports\n$source',
      );
      paths.add(path);
    }
    for (final path in compiles ? paths : const <String>[]) {
      final unit = await host.session.getResolvedUnit(host.absolute(path));
      final errors = (unit as ResolvedUnitResult).diagnostics.where(
        (diagnostic) => diagnostic.severity == Severity.error,
      );
      expect(errors, isEmpty, reason: '$path does not compile');
    }
    final lines = await breachesIn(host, paths, {
      for (final name in exempt) name: 'a reason',
    });
    return [for (final line in lines) line.replaceAll('$at/', '')];
  }
}

/// The line for a provider that reads the repository unkeyed.
String unkeyed(String name, {String file = 'a.dart'}) =>
    '$file: $name reads the repository without watching '
    'signedInAccountProvider';

/// The line for a provider whose build the scan cannot determine.
Matcher undetermined(String name, {String file = 'a.dart'}) => allOf(
  startsWith('$file: $name has a build the scan cannot determine ('),
  endsWith('); it fails closed on what it cannot read'),
);

/// A provider whose rows change on their own, for a listener to hear.
const clock = 'final clockProvider = Provider<int>((ref) => 0);';

/// A library with the notifier `Lists`, declared by [header], and its
/// kept-alive provider `listsProvider`. Its build runs [build], which reads
/// the repository unless it is given.
String lists({
  String before = '',
  String header = 'Lists extends AsyncNotifier<Object>',
  String build = 'return $read;',
  String members = '',
}) =>
    '''
$before

class $header {
  @override
  Future<Object> build() async {
    $build
  }

  $members
}

final listsProvider = AsyncNotifierProvider<Lists, Object>(Lists.new);
''';
