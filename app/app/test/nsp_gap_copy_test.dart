import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/playlists/nsp_gap_copy.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations es;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    es = await AppLocalizations.delegate.load(const Locale('es'));
  });

  NspGap gap(
    String code, {
    String? field,
    String? op,
    Object? value,
    String? key,
    String? mode,
  }) => NspGap(
    kind: 'field',
    code: code,
    path: '/root/nodes/0',
    reason: 'the server sentence',
    field: field,
    op: op,
    value: value,
    key: key,
    mode: mode,
  );

  test('every code the contract lists has words of its own', () {
    final codes = _specNspCodes();
    expect(codes, contains('unsupported_field'));
    expect(codes.length, greaterThan(30));

    final missing = <String>[];
    for (final code in codes) {
      final g = gap(
        code,
        field: 'genre',
        op: 'is',
        value: 3,
        key: 'all',
        mode: 'minutes',
      );
      for (final l10n in <AppLocalizations>[en, es]) {
        for (final export in <bool>[true, false]) {
          if (nspGapSentence(l10n, g, export: export) == g.reason) {
            missing.add('$code ${l10n.localeName} export=$export');
          }
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'these fall back to the server\'s English sentence; add a key to '
          'both ARBs and an arm to nsp_gap_copy.dart:\n${missing.join('\n')}',
    );
  });

  test('a code this build does not know keeps the server sentence', () {
    expect(
      nspGapSentence(en, gap('holographic_field'), export: true),
      'the server sentence',
    );
  });

  test('an export names the rule field, an import the document\'s word', () {
    expect(
      nspGapSentence(
        en,
        gap('unsupported_field', field: 'mediaType'),
        export: true,
      ),
      'NSP has no field for Media type.',
    );
    expect(
      nspGapSentence(
        en,
        gap('unsupported_field', field: 'bitrate'),
        export: false,
      ),
      '"bitrate" is not a field WaxDeck can read.',
    );
    // An older export's name for the star, which NSP calls loved.
    final starred = gap('unsupported_field', field: 'starred');
    expect(
      nspGapSentence(en, starred, export: false),
      '"starred" is not an NSP field; NSP calls the star "loved".',
    );
    expect(
      nspGapSentence(es, starred, export: false),
      '"starred" no es un campo de NSP; allí los favoritos se llaman "loved".',
    );
  });

  test('an export words the operator as the rule editor does', () {
    expect(
      nspGapSentence(
        en,
        gap('presence_operator', field: 'trackNumber', op: 'isMissing'),
        export: true,
      ),
      'In NSP, Track number always holds a value, so "is not set" has no '
      'form there.',
    );
    expect(
      nspGapSentence(
        en,
        gap('presence_operator', field: 'tracknumber', op: 'isMissing'),
        export: false,
      ),
      'Navidrome allows "isMissing" only on a field that can be empty, not '
      'on "tracknumber".',
    );
  });

  test('a budget limit names its unit and a sort term its field', () {
    expect(
      nspGapSentence(
        en,
        gap('limit_budget', value: 60, mode: 'minutes'),
        export: true,
      ),
      'The limit of 60 minutes goes too: NSP would read it as 60 items.',
    );
    expect(
      nspGapSentence(
        en,
        gap(
          'extra_sort_term',
          field: 'title',
          value: const <String, Object?>{'field': 'title', 'desc': false},
        ),
        export: true,
      ),
      'NSP sorts by one field only, so the later sort by Title goes.',
    );
  });

  test('a value reads as the document wrote it', () {
    expect(
      nspGapSentence(
        en,
        gap('value_not_numeric', field: 'rating', value: 'five'),
        export: false,
      ),
      '"rating" takes a number, and "five" is not one.',
    );
    expect(
      nspGapSentence(
        en,
        gap('duration_not_whole_ms', field: 'duration', value: 180.0005),
        export: false,
      ),
      '180.0005 seconds is not a whole number of milliseconds, so it cannot '
      'carry over.',
    );
  });

  test('a mode or a value it has no word for still names what it is', () {
    expect(
      nspGapSentence(en, gap('limit_mode', value: 'gigabytes'), export: true),
      'NSP limits only by number of items, so the limit by "gigabytes" goes.',
    );
    expect(
      nspGapSentence(
        en,
        gap('value_too_large', field: 'rating', op: 'gt', value: 1e300),
        export: true,
      ),
      '1e+300 for Rating is too large to carry over.',
    );
  });

  test('each sentence says what crosses, true for its direction', () {
    expect(
      nspGapSentence(
        en,
        gap('value_not_boolean', field: 'album', op: 'isMissing', value: 'x'),
        export: false,
      ),
      '"isMissing" on "album" takes true or false, not "x".',
    );
    expect(
      nspGapSentence(
        en,
        gap('date_operator', field: 'dateAdded', op: 'before'),
        export: false,
      ),
      '"before" on "dateAdded" cannot carry over, since only "inTheLast" and '
      '"notInTheLast" do on a date.',
    );
    expect(
      nspGapSentence(
        en,
        gap('unsupported_operator', field: 'title', op: 'inTheLast'),
        export: false,
      ),
      '"inTheLast" on "title" has no WaxDeck form.',
    );
    expect(
      nspGapSentence(
        en,
        gap('boolean_operator', field: 'starred', op: 'gt'),
        export: true,
      ),
      'Starred is yes or no, so it takes only "is" and "is not".',
    );
    expect(
      nspGapSentence(
        en,
        gap('boolean_operator', field: 'loved', op: 'gt'),
        export: false,
      ),
      '"loved" is yes or no, so it takes only "is" and "isNot".',
    );
  });
}

/// The reason codes the committed bundle lists for `NspGap.code`.
Set<String> _specNspCodes() {
  final spec = File(_repoFile('api/openapi.yaml')).readAsStringSync();
  const opening = "The catalog's codes are";
  final start = spec.indexOf(opening);
  expect(start, isNonNegative, reason: 'the spec no longer says "$opening"');
  final end = spec.indexOf('.', start);
  return RegExp(
    r'`([a-z_]+)`',
  ).allMatches(spec.substring(start, end)).map((m) => m.group(1)!).toSet();
}

/// A repo-relative path, resolved by walking up from `app/app`.
String _repoFile(String relative) {
  var dir = Directory.current;
  for (var up = 0; up < 6; up++) {
    final candidate = File('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  throw StateError('no $relative above ${Directory.current.path}');
}
