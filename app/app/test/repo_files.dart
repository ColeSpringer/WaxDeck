import 'dart:io';

/// A repo-relative path, resolved by walking up from `app/app`, which is
/// where the tests run.
String repoFile(String relative) {
  var dir = Directory.current;
  for (var up = 0; up < 6; up++) {
    final candidate = File('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  throw StateError('no $relative above ${Directory.current.path}');
}

/// The committed bundle's text with every run of whitespace one space,
/// for the tests that read a list out of its prose.
///
/// Its descriptions are folded scalars: a sentence breaks across lines
/// wherever a fragment's author wrapped it, and only the YAML joins it
/// again. Collapsed, a reader's fixed sentence is found however the
/// paragraph around it wraps.
String specProse() {
  final bundle = File(repoFile('api/openapi.yaml')).readAsStringSync();
  return bundle.replaceAll(RegExp(r'\s+'), ' ');
}
