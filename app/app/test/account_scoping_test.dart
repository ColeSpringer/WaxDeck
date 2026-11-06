import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A kept-alive provider that fetches per-account rows must be keyed on the
/// account.
///
/// The repository moves only with the server, so a second account signing
/// in on the same server leaves every kept-alive provider holding the
/// first one's rows unless its build watches `signedInAccountProvider`.
/// Nothing in the compiler says so, and `account_reads_test.dart` only
/// covers the providers somebody remembered. This scan reads every
/// top-level provider in `lib`, and fails one that is kept alive, reaches
/// `repositoryProvider` from its build and does not watch the account,
/// unless [_sameForEveryAccount] names it with the reason its rows are the
/// same for every account. A provider that is exempt but no longer needs
/// to be fails too, so the map cannot rot.
///
/// A notifier is read through its `build` and the methods of its class
/// that `build` calls (following `extends` to a base class that has one),
/// whether the declaration tears its constructor off, calls it from a
/// closure, or names the class only as its first type argument; a class
/// with no `build` at all is read whole, since its constructor is where it
/// starts. Only `ref.watch(signedInAccountProvider)` keys a provider: a
/// read does not rebuild it. A notifier the scan cannot name or find,
/// private or not, fails rather than passes.
void main() {
  test('every kept-alive provider that reads the repository is keyed on the '
      'account or says why not', () {
    final breaches = _breaches(_libSources(), _sameForEveryAccount);
    expect(
      breaches,
      isEmpty,
      reason:
          'A kept-alive provider that reads the repository from its build '
          'must `ref.watch(signedInAccountProvider)` there, or be named in '
          '_sameForEveryAccount with the reason its rows are the same for '
          'every account.\n\n${breaches.join('\n')}',
    );
  });

  test('every exemption has a reason', () {
    expect(
      _sameForEveryAccount.entries.where((e) => e.value.trim().isEmpty),
      isEmpty,
    );
  });

  group('the scan', () {
    List<String> scan(
      Map<String, String> sources, {
      Set<String> exempt = const {},
    }) => _breaches(sources, {for (final name in exempt) name: 'a reason'});

    test('flags a kept-alive provider that forgets the watch', () {
      final breaches = scan({
        'a.dart': '''
final listsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(repositoryProvider).lists(),
);
''',
      });
      expect(breaches, hasLength(1));
      expect(breaches.single, contains('listsProvider'));
    });

    test('flags a notifier whose build forgets the watch', () {
      final breaches = scan({
        'a.dart': '''
class Lists extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() => ref.watch(repositoryProvider).lists();
}

final listsProvider = AsyncNotifierProvider<Lists, List<String>>(Lists.new);
''',
      });
      expect(breaches.single, contains('listsProvider'));
    });

    test('flags a family and a build that only reads the repository', () {
      final breaches = scan({
        'a.dart': '''
final oneProvider = FutureProvider.family<String, String>(
  (ref, pid) => ref.watch(repositoryProvider).one(pid),
);

class Quiet extends Notifier<int> {
  @override
  int build() {
    ref.read(repositoryProvider);
    return 0;
  }
}

final quietProvider = NotifierProvider<Quiet, int>(Quiet.new);
''',
      });
      expect(breaches, hasLength(2));
    });

    test('passes a provider that watches the account', () {
      expect(
        scan({
          'a.dart': '''
final listsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(signedInAccountProvider);
  return ref.watch(repositoryProvider).lists();
});

class Lists extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    ref.watch(signedInAccountProvider);
    return ref.watch(repositoryProvider).count();
  }
}

final countProvider = AsyncNotifierProvider<Lists, int>(Lists.new);
''',
        }),
        isEmpty,
      );
    });

    test('a watch named only in a comment does not count', () {
      final breaches = scan({
        'a.dart': '''
final listsProvider = FutureProvider<List<String>>((ref) {
  // ref.watch(signedInAccountProvider);
  /* ref.watch(signedInAccountProvider) */
  return ref.watch(repositoryProvider).lists();
});
''',
      });
      expect(breaches, hasLength(1));
    });

    test('ignores a provider that is autoDispose or never reads the '
        'repository', () {
      expect(
        scan({
          'a.dart': '''
final shortProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(repositoryProvider).count(),
);

final otherProvider = Provider<int>((ref) => ref.watch(clockProvider));
''',
        }),
        isEmpty,
      );
    });

    test('a named exemption passes, and goes stale when it is not needed', () {
      const source = '''
final listsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(repositoryProvider).lists(),
);
final fineProvider = Provider<int>((ref) => 1);
''';
      expect(scan({'a.dart': source}, exempt: {'listsProvider'}), isEmpty);

      final stale = scan({'a.dart': source}, exempt: {'fineProvider'});
      expect(stale, hasLength(2));
      expect(stale.join('\n'), contains('fineProvider'));
      expect(stale.join('\n'), contains('drop'));
      expect(
        scan({'a.dart': source}, exempt: {'listsProvider', 'goneProvider'}),
        hasLength(1),
      );
    });

    test('follows a notifier to the base class that has the build', () {
      final breaches = scan({
        'a.dart': '''
abstract class Base extends AsyncNotifier<int> {
  @override
  Future<int> build() => ref.watch(repositoryProvider).count();
}

class Child extends Base {}

final childProvider = AsyncNotifierProvider<Child, int>(Child.new);
''',
      });
      expect(breaches.single, contains('childProvider'));
    });

    test('reads a class with no build whole', () {
      final breaches = scan({
        'a.dart': '''
class Service {
  Service(this._ref);
  final Ref _ref;
  void go() => _ref.read(repositoryProvider).go();
}

final serviceProvider = Provider<Service>(Service.new);
''',
      });
      expect(breaches.single, contains('serviceProvider'));
    });

    test('flags a private notifier whose build forgets the watch', () {
      final breaches = scan({
        'a.dart': '''
class _Lists extends AsyncNotifier<int> {
  @override
  Future<int> build() => ref.watch(repositoryProvider).count();
}

final listsProvider = AsyncNotifierProvider<_Lists, int>(_Lists.new);
''',
      });
      expect(breaches.single, contains('listsProvider'));
    });

    test('fails closed on a private notifier it cannot find', () {
      final breaches = scan({
        'a.dart':
            'final mysteryProvider = NotifierProvider<_Gone, int>(_Gone.new);',
      });
      expect(breaches.single, contains('cannot'));
    });

    test('counts a read in a helper the build calls as the build\'s', () {
      const helper = '''
class Lists extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    return _fetch();
  }

  Future<int> _fetch() => ref.watch(repositoryProvider).count();
  Future<int> _unrelated() => ref.watch(repositoryProvider).count();
}

final listsProvider = AsyncNotifierProvider<Lists, int>(Lists.new);
''';
      expect(scan({'a.dart': helper}).single, contains('listsProvider'));

      // Followed through a second helper, and satisfied by the watch
      // wherever the build's reach has it.
      expect(
        scan({
          'a.dart': helper.replaceFirst(
            'return _fetch();',
            'ref.watch(signedInAccountProvider);\n    return _fetch();',
          ),
        }),
        isEmpty,
      );
      expect(
        scan({
          'a.dart': helper
              .replaceFirst('return _fetch();', 'return _outer();')
              .replaceFirst(
                'Future<int> _fetch()',
                'Future<int> _outer() => _fetch();\n  Future<int> _fetch()',
              ),
        }).single,
        contains('listsProvider'),
      );
    });

    test('a helper the build does not call is not the build\'s', () {
      expect(
        scan({
          'a.dart': '''
class Lists extends AsyncNotifier<int> {
  @override
  Future<int> build() async => 0;

  Future<int> refresh() => ref.read(repositoryProvider).count();
}

final listsProvider = AsyncNotifierProvider<Lists, int>(Lists.new);
''',
        }),
        isEmpty,
      );
    });

    test('a ref.read of the account is not a watch', () {
      final breaches = scan({
        'a.dart': '''
final listsProvider = FutureProvider<List<String>>((ref) {
  ref.read(signedInAccountProvider);
  return ref.watch(repositoryProvider).lists();
});
''',
      });
      expect(breaches.single, contains('listsProvider'));
    });

    test('fails closed on a notifier it cannot find', () {
      final breaches = scan({
        'a.dart':
            'final mysteryProvider = NotifierProvider<Gone, int>(Gone.new);',
      });
      expect(breaches.single, contains('mysteryProvider'));
      expect(breaches.single, contains('cannot'));
    });

    test('follows a notifier its declaration builds in a closure', () {
      String source(String keyed) =>
          '''
class Lists extends AsyncNotifier<int> {
  Lists({this.all = false});

  final bool all;

  @override
  Future<int> build() async {
    $keyed
    return ref.watch(repositoryProvider).count(all: all);
  }
}

final allListsProvider = AsyncNotifierProvider<Lists, int>(
  () => Lists(all: true),
  retry: (_, _) => null,
);
''';
      expect(scan({'a.dart': source('')}).single, contains('allListsProvider'));
      // Satisfied by the watch in the class it builds, as a tear-off is.
      expect(
        scan({'a.dart': source('ref.watch(signedInAccountProvider);')}),
        isEmpty,
      );
      // The class the closure builds, not the type it is declared as.
      expect(
        scan({
          'a.dart': '''
abstract class Base extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    ref.watch(signedInAccountProvider);
    return 0;
  }
}

class Every extends Base {
  @override
  Future<int> build() => ref.watch(repositoryProvider).count();
}

final everyProvider = AsyncNotifierProvider<Base, int>(() => Every());
''',
        }).single,
        contains('everyProvider'),
      );
    });

    test('names the notifier by its type when a helper builds it', () {
      final breaches = scan({
        'a.dart': '''
class Lists extends Notifier<int> {
  @override
  int build() {
    ref.read(repositoryProvider);
    return 0;
  }
}

Lists _everyList() => Lists();

final listsProvider = NotifierProvider<Lists, int>(
  _everyList,
  retry: (count, _) => Duration(seconds: count),
);
''',
      });
      // Read through Lists: a later argument's closure is not the notifier.
      expect(breaches.single, contains('listsProvider reads the repository'));
    });

    test('fails closed on a closure-built notifier it cannot name or '
        'find', () {
      final breaches = scan({
        'a.dart': '''
final goneProvider = NotifierProvider<Gone, int>(() => Gone(1));
final untypedProvider = NotifierProvider(() => _make());
''',
      });
      expect(breaches, hasLength(2));
      expect(breaches.join('\n'), contains('goneProvider'));
      expect(breaches.join('\n'), contains('untypedProvider'));
      expect(breaches, everyElement(contains('cannot')));
    });
  });
}

/// Providers that read the repository from a kept-alive build and answer
/// the same for every account, each with why.
const Map<String, String> _sameForEveryAccount = <String, String>{
  // Server-wide data: every account that can read it sees the same rows.
  'adminJobsProvider': _serverWide,
  'adminSettingsProvider': _serverWide,
  'adminUsersProvider': _serverWide,
  'auditProvider': _serverWide,
  'backupsProvider': _serverWide,
  'catalogCheckProvider': _serverWide,
  'diagnosticSummaryProvider': _serverWide,
  'diagnosticsProvider': _serverWide,
  'duplicatesProvider': _serverWide,
  'genreTreeProvider': _serverWide,
  'healthProvider': _serverWide,
  'invitesProvider': _serverWide,
  'libraryCountsProvider': _serverWide,
  'libraryMatchingProvider': _serverWide,
  'librariesProvider': _serverWide,
  'notifyEventCatalogProvider': _serverWide,
  'organizeProfilesProvider': _serverWide,
  'schedulesProvider': _serverWide,
  'scrobblingAdminConfigProvider': _serverWide,
  'serverHealthProvider': _serverWide,
  'serverNotificationTargetsProvider': _serverWide,
  'signupRequestsProvider': _serverWide,
  'similarityStatusProvider': _serverWide,
  'stagedRestoreProvider': _serverWide,
  'thumbnailCacheProvider': _serverWide,
  'transcodingActivityProvider': _serverWide,
  'transcodingLimitsProvider': _serverWide,
  'trashProvider': _serverWide,
  'upgradesProvider': _serverWide,
  // The server's own vocabulary and capabilities.
  'ruleFieldsProvider': _serverVocabulary,
  'uploadFormatSetsProvider': _serverVocabulary,
  // Stations are shared by all users, as the API spec says.
  'radioStationsProvider': _serverWide,
  // Read before any account exists, or by the sign-in screen itself.
  'bootstrapStatusProvider': _beforeSignIn,
  'oidcFlowProvider': _beforeSignIn,
  'oidcProvidersProvider': _beforeSignIn,
  // Probes the unauthenticated health endpoint for the server's build.
  'serverUpdatedProvider': _unauthenticatedProbe,
  // The account's own source, and what follows it through that.
  'authControllerProvider': _accountSource,
  'myAccountProvider': _followsAuth,
  'prefsControllerProvider': _followsAuth,
  // The public podcast and radio directories: no account's rows.
  'podcastDirectoryResultsProvider': _publicDirectory,
  'radioDirectoryResultsProvider': _radioDirectory,
  // Playback and device state that sign-out already resets.
  'artworkStoreProvider': _deviceState,
  'nowPlayingProvider': _deviceState,
  'queueRecheckProvider': _deviceState,
  // The offer is the account's last playback sessions, from the server.
  'queueRestoreProvider': _clearedLeavingAccount,
  'queueSourcePagerProvider': _deviceState,
  'radioNowPlayingArtProvider': _deviceState,
  // Plumbing that outlives an account: the repository itself, and the
  // pieces whose account is set once per session by their binder.
  'discordCoversProvider': _infrastructure,
  'downloadManagerProvider': _infrastructure,
  'repositoryProvider': _infrastructure,
  'syncEngineProvider': _infrastructure,
  // Whether the server takes the compound save: a capability of the server.
  'compoundSaveProvider': _serverVocabulary,
};

const _serverWide =
    'server-wide data: every account that can read it sees the same rows';
const _serverVocabulary =
    'the server\'s own vocabulary or capabilities, the same for every account';
const _beforeSignIn =
    'read before any account exists, or by the sign-in screen';
const _unauthenticatedProbe =
    'reads the unauthenticated health endpoint, which answers every '
    'account alike';
const _clearedLeavingAccount =
    'its rows are the account\'s own, but every road out of the account '
    '(a sign-out, a session the server ended, another account\'s session '
    'in its place, a dead stored one at launch) invalidates it through '
    'forgetQueueOnSignOut before another account\'s session is adopted';
const _accountSource = 'the source the account is derived from';
const _followsAuth =
    'follows the account through authControllerProvider, which it watches';
const _publicDirectory =
    'a public directory search: no account\'s rows are in it';
const _radioDirectory =
    'public directory rows; only their order follows the caller\'s locale '
    'region, and none of the caller\'s own data is in them';
const _deviceState =
    'playback or device state that sign-out resets, not an account\'s rows';
const _infrastructure =
    'plumbing that outlives an account; its account is set per session';

/// Where the sources are read from, relative to the app package.
const _libRoot = 'lib';

Map<String, String> _libSources() => <String, String>{
  for (final file in Directory(_libRoot).listSync(recursive: true))
    if (file is File &&
        file.path.endsWith('.dart') &&
        !file.path.endsWith('.g.dart') &&
        !file.path.contains(
          '${Platform.pathSeparator}l10n${Platform.pathSeparator}',
        ))
      file.path.split(Platform.pathSeparator).join('/'): file
          .readAsStringSync(),
};

/// One line per breach of the rule, in [sources], given the providers
/// [exempt] from it.
List<String> _breaches(
  Map<String, String> sources,
  Map<String, String> exempt,
) {
  final code = <String, String>{
    for (final MapEntry(:key, :value) in sources.entries)
      key: _blankComments(value),
  };
  final breaches = <String>[];
  final unkeyed = <String>{};

  final declaration = RegExp(r'^final\s+(\w+Provider)\s*=', multiLine: true);
  for (final MapEntry(key: path, value: text) in code.entries) {
    for (final match in declaration.allMatches(text)) {
      final name = match.group(1)!;
      final decl = text.substring(match.start, _statementEnd(text, match.end));
      if (decl.contains('autoDispose')) continue;
      final String? reach;
      final built = _builtClass(decl);
      if (built == null && !_notifierDeclaration.hasMatch(decl)) {
        reach = decl;
      } else {
        reach = built == null ? null : _buildOf(code, built);
        if (reach == null) {
          breaches.add(
            built == null
                ? '$path: $name builds a notifier the scan cannot name; it '
                      'fails closed on what it cannot read'
                : '$path: $name constructs $built, which the scan cannot '
                      'find; it fails closed on what it cannot read',
          );
          continue;
        }
      }
      if (reach.contains('repositoryProvider') &&
          !_watchesAccount.hasMatch(reach)) {
        unkeyed.add(name);
        if (!exempt.containsKey(name)) {
          breaches.add(
            '$path: $name reads the repository without watching '
            'signedInAccountProvider',
          );
        }
      }
    }
  }
  for (final name in exempt.keys) {
    if (!unkeyed.contains(name)) {
      breaches.add(
        '$name is exempt, but it is not a kept-alive provider that reads the '
        'repository unkeyed (any more): drop the entry',
      );
    }
  }
  return breaches;
}

/// A declaration whose state is a notifier's, read through its class.
final _notifierDeclaration = RegExp(
  r'^final\s+\w+\s*=\s*(?:Async|Stream)?NotifierProvider\b',
);

/// The class a declaration builds: the one it tears off with `.new`, or
/// for a notifier the one its first argument constructs, else the one its
/// first type argument names. Null for a provider whose body is its build,
/// and for a notifier that names no class.
String? _builtClass(String decl) {
  final tornOff = RegExp(r'\b(_?[A-Z]\w*)\.new\b').firstMatch(decl);
  if (tornOff != null) return tornOff.group(1);
  final kind = _notifierDeclaration.firstMatch(decl);
  if (kind == null) return null;
  final called = RegExp(
    r'(?:=>|\breturn\b)\s*(_?[A-Z]\w*)\s*(?:\.\s*\w+\s*)?\(',
  ).firstMatch(_firstArgument(decl, kind.end));
  final typed = RegExp(
    r'^[\w.\s]*<\s*(_?[A-Z]\w*)',
  ).firstMatch(decl.substring(kind.end));
  return called?.group(1) ?? typed?.group(1);
}

/// The first argument of the call that opens after [from], past its type
/// arguments: for a notifier provider, what builds the notifier.
String _firstArgument(String decl, int from) {
  var angles = 0;
  for (var open = from; open < decl.length; open++) {
    if (decl[open] == '<') angles++;
    if (decl[open] == '>') angles--;
    if (decl[open] != '(' || angles > 0) continue;
    var depth = 0;
    for (var i = open + 1; i < decl.length; i++) {
      i = _pastString(decl, i);
      if (i >= decl.length) break;
      final c = decl[i];
      if (c == '(' || c == '[' || c == '{') {
        depth++;
      } else if (c == ')' || c == ']' || c == '}') {
        if (depth == 0) return decl.substring(open + 1, i);
        depth--;
      } else if (c == ',' && depth == 0) {
        return decl.substring(open + 1, i);
      }
    }
    return decl.substring(open + 1);
  }
  return '';
}

/// The text a notifier or service named by [className] starts from: its
/// `build`, the nearest one up its `extends` chain, or the whole class
/// when none has one. Null when the class is not in [code].
String? _buildOf(Map<String, String> code, String className) {
  final seen = <String>{};
  String? name = className;
  while (name != null && seen.add(name)) {
    final found = _classOf(code, name);
    if (found == null) return null;
    final (:header, :body) = found;
    final build = RegExp(
      r'\bbuild\s*\([^)]*\)\s*(async\s*)?(\{|=>)',
    ).firstMatch(body);
    if (build != null) {
      return _withHelpers(
        body,
        build.group(2) == '=>'
            ? body.substring(build.start, _statementEnd(body, build.end))
            : _block(body, build.end - 1),
      );
    }
    final base = RegExp(r'\bextends\s+(\w+)').firstMatch(header)?.group(1);
    if (base == null || _classOf(code, base) == null) return body;
    name = base;
  }
  return null;
}

/// Only a watch keys a provider on the account: a read does not rebuild it.
final _watchesAccount = RegExp(
  r'\bref\s*\.\s*watch\s*\(\s*signedInAccountProvider\b',
);

const _keywords = <String>{
  'if',
  'for',
  'while',
  'switch',
  'catch',
  'return',
  'await',
  'assert',
};

/// [build] and the methods of its class that it calls, however deep, so
/// a read in a helper is the build's.
String _withHelpers(String body, String build) {
  final seen = <String>{};
  var text = build;
  for (var grew = true; grew;) {
    grew = false;
    final calls = RegExp(
      r'(?<![.\w])(_?\w+)\s*\(',
    ).allMatches(text).map((m) => m.group(1)!).toSet();
    for (final call in calls) {
      if (_keywords.contains(call) || !seen.add(call)) continue;
      final def = RegExp(
        '(?<![.\\w])$call\\s*\\([^)]*\\)\\s*(?:async\\s*)?(\\{|=>)',
      ).firstMatch(body);
      if (def == null) continue;
      text += def.group(1) == '=>'
          ? '\n${body.substring(def.start, _statementEnd(body, def.end))}'
          : '\n${_block(body, def.end - 1)}';
      grew = true;
    }
  }
  return text;
}

({String header, String body})? _classOf(
  Map<String, String> code,
  String name,
) {
  final declaration = RegExp('\\bclass\\s+$name\\b([^{]*)\\{');
  for (final text in code.values) {
    final match = declaration.firstMatch(text);
    if (match != null) {
      return (header: match.group(1)!, body: _block(text, match.end - 1));
    }
  }
  return null;
}

/// The balanced `{...}` that opens at [open].
String _block(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    i = _pastString(text, i);
    if (i >= text.length) break;
    if (text[i] == '{') {
      depth++;
    } else if (text[i] == '}') {
      depth--;
      if (depth == 0) return text.substring(open, i + 1);
    }
  }
  return text.substring(open);
}

/// Where the statement that runs through [from] ends: its `;` outside any
/// bracket.
int _statementEnd(String text, int from) {
  var depth = 0;
  for (var i = from; i < text.length; i++) {
    i = _pastString(text, i);
    if (i >= text.length) break;
    final c = text[i];
    if (c == '(' || c == '[' || c == '{') {
      depth++;
    } else if (c == ')' || c == ']' || c == '}') {
      depth--;
    } else if (c == ';' && depth <= 0) {
      return i;
    }
  }
  return text.length;
}

/// [i], or the index just past the string literals that start there.
int _pastString(String text, int i) {
  while (i < text.length && (text[i] == "'" || text[i] == '"')) {
    final quote = text[i];
    i++;
    while (i < text.length && text[i] != quote) {
      i += text[i] == r'\' ? 2 : 1;
    }
    i++;
  }
  return i;
}

/// [source] with its comments blanked to spaces, so offsets and lines hold.
String _blankComments(String source) => source
    .replaceAllMapped(
      RegExp(r'/\*[\s\S]*?\*/'),
      (m) => m.group(0)!.replaceAll(RegExp(r'[^\n]'), ' '),
    )
    .replaceAllMapped(
      RegExp(
        r'(?<![:\w'
        "'"
        r'"])//[^\n]*',
      ),
      (m) => ' ' * m.group(0)!.length,
    );
