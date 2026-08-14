import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/health/health_labels.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/settings/notify_labels.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

/// The error table, and the two token tables shaped like it.
///
/// The completeness check reads the contract rather than a second copy of
/// it. A duplicated list of codes would be a third place the vocabulary
/// lives (spec prose, explainer, list) and would go stale silently,
/// because an unknown code falling back to the server's message is by
/// design and so reports nothing. Reading the committed bundle means a
/// code added on the server side fails here, asking for a translation.
void main() {
  late AppLocalizations en;
  late AppLocalizations es;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    es = await AppLocalizations.delegate.load(const Locale('es'));
  });

  group('explainError', () {
    test('every code the contract defines has a sentence', () {
      final codes = _specCodes();
      // A guard on the guard: a parse that quietly found nothing would
      // pass every assertion under it.
      expect(codes, contains('not-found'));
      expect(codes.length, greaterThan(15));

      final missing = <String>[];
      for (final code in codes) {
        for (final l10n in <AppLocalizations>[en, es]) {
          final answer = explainError(l10n, _fake(code));
          if (answer == _serverMessage) {
            missing.add('$code (${l10n.localeName})');
          }
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'these codes fall through to the server\'s English sentence; add '
            'an arm to explain_error.dart and a key to both ARBs:\n'
            '${missing.join('\n')}',
      );
    });

    test('the codes this client mints for itself have one too', () {
      // Deliberately absent from the contract's list: nothing on the
      // server can produce them, so the check above cannot see them.
      // `waxdeck_api` owns the transport three; the `local-` ones name a
      // failure of this device, and they are why nothing here borrows a
      // spec code for a failure the server never reported.
      for (final code in const <String>[
        'transport',
        'transport-timeout',
        'transport-empty',
        'local-channel-offline',
        'local-command-timeout',
        'local-unregistered',
      ]) {
        expect(explainError(en, _fake(code)), isNot(_serverMessage));
        expect(explainError(es, _fake(code)), isNot(_serverMessage));
      }
    });

    test('the app mints no spec code for a failure of its own', () {
      // The trap this namespace exists to close: a locally-minted spec
      // code would be worded as if the server had said it, so a listener
      // whose own socket dropped would be told an outside service is
      // down. Scanned rather than reasoned about, because the next mint
      // is written by somebody who has not read this.
      final codes = _specCodes();
      final offenders = <String>[];
      for (final file in _appSources()) {
        final source = file.readAsStringSync();
        for (final match in RegExp(
          r"code:\s*'([a-z][a-z-]*)'",
        ).allMatches(source)) {
          final code = match.group(1)!;
          if (!codes.contains(code)) continue;
          if (_wireCodeFiles.any(file.path.replaceAll('\\', '/').endsWith)) {
            continue;
          }
          offenders.add('${file.path}: $code');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'these mint a code the contract defines for a failure this '
            'device had; give it a `local-` name and a sentence, or add '
            'the file to _wireCodeFiles if the code is going out over the '
            'connect socket:\n${offenders.join('\n')}',
      );
    });

    test('an unknown code keeps the server sentence', () {
      // The contract says unknown codes stay opaque, and English prose
      // beats a shrug.
      expect(explainError(en, _fake('holo-cube')), _serverMessage);
    });

    test('anything that is not an API failure gets the generic line', () {
      expect(explainError(en, StateError('boom')), en.errorUnexpected);
      expect(explainError(es, 'a bare string'), es.errorUnexpected);
    });

    test('feature-unavailable is refined by its params, not its prose', () {
      const umbrella = WaxDeckApiException(
        code: 'feature-unavailable',
        message: _serverMessage,
      );
      expect(explainError(en, umbrella), en.errorFeatureUnavailable);

      const book = WaxDeckApiException(
        code: 'feature-unavailable',
        message: _serverMessage,
        params: <String, String>{
          'feature': 'multi-part-audiobook',
          'pid': 'bk-1',
        },
      );
      expect(explainError(en, book), en.errorMultiPartAudiobook);
      expect(explainError(es, book), es.errorMultiPartAudiobook);

      const window = WaxDeckApiException(
        code: 'feature-unavailable',
        message: _serverMessage,
        params: <String, String>{'feature': 'windowed-track'},
      );
      expect(explainError(en, window), en.errorWindowedTrack);

      // A feature named by a newer server is still a feature-unavailable.
      const later = WaxDeckApiException(
        code: 'feature-unavailable',
        message: _serverMessage,
        params: <String, String>{'feature': 'holo-projection'},
      );
      expect(explainError(en, later), en.errorFeatureUnavailable);
    });
  });

  group('explainRefusal', () {
    test('a refused value keeps the sentence naming it', () {
      // The endpoints that validate say which value refused, and that is
      // the whole use of a form's error line. Translating the code would
      // leave a 200-genre tree with nothing to search for.
      const refused = WaxDeckApiException(
        code: 'invalid-request',
        message: 'cron field 4 is not a weekday',
        statusCode: 400,
      );
      expect(explainRefusal(en, refused), 'cron field 4 is not a weekday');
      expect(explainRefusal(es, refused), 'cron field 4 is not a weekday');
    });

    test('a claimed path keeps the conflict that names it', () {
      const taken = WaxDeckApiException(
        code: 'conflict',
        message: 'library "Vinyl" already covers /srv/media',
        statusCode: 409,
      );
      expect(explainRefusal(en, taken), contains('/srv/media'));
    });

    test('anything else reads from the table', () {
      // Not a refusal of an input: there is nothing for the server to
      // name, and its own wording is English.
      const failed = WaxDeckApiException(
        code: 'catalog-maintenance',
        message: 'the catalog is being rebuilt',
        statusCode: 503,
      );
      expect(explainRefusal(en, failed), en.errorCatalogMaintenance);
      expect(explainRefusal(es, failed), es.errorCatalogMaintenance);
      expect(explainRefusal(en, StateError('x')), en.errorUnexpected);
    });

    test('a refusal with nothing to say falls back to the table', () {
      const bare = WaxDeckApiException(
        code: 'invalid-request',
        message: '   ',
        statusCode: 400,
      );
      expect(explainRefusal(en, bare), en.errorInvalidRequest);
    });
  });

  group('health rule labels', () {
    HealthRuleCount rule(String token, {String? label}) =>
        HealthRuleCount(rule: token, failing: 1, fixable: false, label: label);

    test('every rule the contract names has a word of its own', () {
      // Read out of the bundle, like the error codes and for the same
      // reason: the fallback to the server's English label is by design,
      // so a rule with no arm reports nothing on its own.
      final rules = _specHealthRules();
      expect(rules, contains('missing-art'));
      expect(rules.length, greaterThan(8));

      final missing = <String>[];
      for (final token in rules) {
        for (final l10n in <AppLocalizations>[en, es]) {
          if (healthRuleName(l10n, token) == null) {
            missing.add('$token (${l10n.localeName})');
          }
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'these rules fall through to the label the server sends, which '
            'is always English; add an arm to health_labels.dart and a key '
            'to both ARBs:\n${missing.join('\n')}',
      );
    });

    test('a known rule takes the client word over the server label', () {
      expect(
        healthRuleLabel(en, rule('missing-art', label: 'Missing cover art')),
        'Missing cover art',
      );
      expect(
        healthRuleLabel(es, rule('missing-art', label: 'Missing cover art')),
        'Sin carátula',
      );
    });

    test('an unknown rule falls back to the label, then to the token', () {
      expect(
        healthRuleLabel(es, rule('holo-check', label: 'Holograms out of true')),
        'Holograms out of true',
      );
      expect(healthRuleLabel(es, rule('holo-check')), 'holo-check');
    });
  });

  group('notification event labels', () {
    NotifyEvent event(String name) =>
        NotifyEvent(name: name, scope: 'user', description: 'From the server.');

    test('a known event gets a title of its own, not the wire token', () {
      expect(notifyEventTitle(en, event('review-ready')), 'Waiting for review');
      expect(
        notifyEventTitle(es, event('review-ready')),
        'Pendiente de revisión',
      );
      expect(
        notifyEventHelp(es, event('review-ready')),
        es.notifReviewReadyHelp,
      );
    });

    test('an unknown event falls back to what the server sent', () {
      expect(notifyEventTitle(es, event('holo-arrived')), 'holo-arrived');
      expect(notifyEventHelp(es, event('holo-arrived')), 'From the server.');
    });
  });
}

/// A message no translation can equal, so "the table answered" and "the
/// fallback answered" are always tellable apart.
const _serverMessage = 'server prose, verbatim, never translated';

WaxDeckApiException _fake(String code) =>
    WaxDeckApiException(code: code, message: _serverMessage);

/// The codes the committed bundle documents, read out of its prose.
///
/// The list lives between two fixed sentences, and every code in it is
/// backticked. Parenthesised descriptions are dropped first: they quote
/// codes too (`catalog-busy` explains itself against a plain `conflict`),
/// and they name a request field - `force` - that is not a code at all.
Set<String> _specCodes() {
  final spec = File(_repoFile('api/openapi.yaml')).readAsStringSync();
  const opening = 'currently defined codes:';
  const closing = 'New codes may appear';
  final start = spec.indexOf(opening);
  expect(start, isNonNegative, reason: 'the spec no longer says "$opening"');
  final end = spec.indexOf(closing, start);
  expect(end, isNonNegative, reason: 'the spec no longer says "$closing"');

  final outside = StringBuffer();
  var depth = 0;
  for (final char in spec.substring(start, end).split('')) {
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
    } else if (depth == 0) {
      outside.write(char);
    }
  }
  return RegExp(
    r'`([a-z][a-z-]*)`',
  ).allMatches(outside.toString()).map((m) => m.group(1)!).toSet();
}

/// The health rules the committed bundle documents, read out of its
/// prose the way the error codes are.
///
/// The health endpoint's description carries the current set, and it is
/// the only machine-readable place they are all written down: the server
/// holds them as Go constants and the schema types the field as a free
/// string, deliberately, so a newer server can add one.
Set<String> _specHealthRules() {
  final spec = File(_repoFile('api/openapi.yaml')).readAsStringSync();
  const opening = 'the current set is';
  final start = spec.indexOf(opening);
  expect(start, isNonNegative, reason: 'the spec no longer says "$opening"');
  final end = spec.indexOf('.', spec.indexOf('`corrupt-audio`', start));
  expect(end, isNonNegative, reason: 'the rule list no longer ends as it did');
  return RegExp(
    r'`([a-z][a-z-]*)`',
  ).allMatches(spec.substring(start, end)).map((m) => m.group(1)!).toSet();
}

/// A repo-relative path, resolved by walking up from `app/app`, which is
/// where this test runs.
String _repoFile(String relative) {
  var dir = Directory.current;
  for (var up = 0; up < 6; up++) {
    final candidate = File('${dir.path}/$relative');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  throw StateError('no $relative above ${Directory.current.path}');
}

/// The files whose `code:` literals are answers going out over the
/// connect socket rather than sentences drawn on this device.
///
/// A client endpoint refusing a remote controller's command replies in
/// the contract's own vocabulary, which is the point: the code crosses
/// the wire and the other end reads it. `account_sections` is here for a
/// narrower reason - `unauthenticated` is exactly what happened, so it
/// is the honest code rather than a borrowed one.
const _wireCodeFiles = <String>[
  'lib/src/connect/connect_controller.dart',
  'lib/src/connect/queue_gateway.dart',
  'lib/src/settings/account_sections.dart',
];

/// Every Dart source in the app, for the scan above.
List<File> _appSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();
