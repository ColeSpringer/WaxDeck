/// go_router's `replace` and `pushReplacement`, by location or by name, go
/// through `context.swap`.
///
/// Either rewrites the visit on screen in the navigation history, but
/// go_router reports it to the browser as a new entry unless it runs under
/// `Router.neglect`, which is what `swap` adds: called bare, browser back
/// walks entries the history does not hold. Nothing in the compiler says
/// so. This reads every library of `lib/` that names either, and fails one
/// that calls or tears off go_router's own (on a `GoRouter` or through its
/// `BuildContext` extension) anywhere but in `swap` itself. A library the
/// scan resolves that does not compile fails too.
library;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'analysis_host.dart';

const _routes = 'lib/src/shell/routes.dart';

/// The rule on `lib/` and on fixtures, over the host [host] returns.
void bareReplaceAudit(AnalysisHost Function() host) {
  test('nothing replaces a location but swap', () async {
    final found = await _replacesIn(host(), libFiles(host()));
    expect(
      found,
      isEmpty,
      reason:
          'A replace is a new browser entry unless it runs under '
          'Router.neglect; context.swap does that.\n\n${found.join('\n')}',
    );
  });

  group('the bare replace check', () {
    var count = 0;
    Future<List<String>> check(String source) async {
      final path = 'lib/bare_replace_fixture${count++}/a.dart';
      host().write(path, '''
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/shell/routes.dart';

$source''');
      final unit = await host().session.getResolvedUnit(host().absolute(path));
      expect(
        (unit as ResolvedUnitResult).diagnostics.where(
          (diagnostic) => diagnostic.severity == Severity.error,
        ),
        isEmpty,
        reason: '$path does not compile',
      );
      return _replacesIn(host(), [path]);
    }

    test('reports a call on either receiver, and a tear-off', () async {
      final found = await check('''
void moves(GoRouter router, BuildContext context) {
  router.replace<void>(WaxRoute.tasks);
  context.replace(WaxRoute.tasks);
  context.pushReplacement(WaxRoute.tasks);
  GoRouter.of(context).pushReplacement<void>(WaxRoute.tasks);
  final later = context.replace;
  later(WaxRoute.tasks);
  router.replaceNamed<void>('tasks');
  context.pushReplacementNamed('tasks');
}
''');
      expect(found, hasLength(7));
      expect(found[0], contains('a.dart:6: replace'));
      expect(found[1], contains('a.dart:7: replace'));
      expect(found[2], contains('a.dart:8: pushReplacement'));
      expect(found[3], contains('a.dart:9: pushReplacement'));
      expect(found[4], contains('a.dart:10: replace'));
      expect(found[5], contains('a.dart:12: replaceNamed'));
      expect(found[6], contains('a.dart:13: pushReplacementNamed'));
    });

    test('leaves swap and every other replace alone', () async {
      final found = await check('''
class Draft {
  void replace(String location) {}
}

void moves(BuildContext context, Draft draft, Uri uri) {
  context.swap(WaxRoute.tasks);
  draft.replace(WaxRoute.tasks);
  uri.replace(path: WaxRoute.tasks);
  WaxRoute.tasks.replaceAll('/', '');
}
''');
      expect(found, isEmpty);
    });

    test('exempts only the swap in routes.dart', () async {
      final found = await check('''
extension on BuildContext {
  void swap(String location) => GoRouter.of(this).replace<void>(location);
}
''');
      expect(found, hasLength(1));
      expect(found.single, contains('a.dart:6: replace'));
    });
  });
}

/// One line per call or tear-off of go_router's `replace` or
/// `pushReplacement` (or their named forms) in [files] outside `swap` in
/// routes.dart, after one per unit, of a library resolved for it, that
/// does not compile. Only a library that names one is resolved.
Future<List<String>> _replacesIn(AnalysisHost host, Iterable<String> files) =>
    goRoutersOwnIn(
      host,
      files,
      names: _replaces,
      exempt: (path, method) => path == _routes && method == 'swap',
      why:
          "is go_router's own, a new browser entry for what the history reads "
          'as the same visit; use context.swap',
    );

const _replaces = {
  'replace',
  'pushReplacement',
  'replaceNamed',
  'pushReplacementNamed',
};

/// One line per call or tear-off of go_router's own method named one of
/// [names] (on a `GoRouter`, its delegate, or through its `BuildContext`
/// extension) in
/// [files], saying [why], except where [exempt] takes the file and the
/// enclosing method; after them one per unit, of a library resolved for
/// it, that does not compile. Only a library that names one is resolved.
Future<List<String>> goRoutersOwnIn(
  AnalysisHost host,
  Iterable<String> files, {
  required Set<String> names,
  required bool Function(String path, String? method) exempt,
  required String why,
}) async {
  final errors = <String>[];
  final found = <String>[];
  for (final file in files) {
    final parsed = host.session.getParsedLibrary(host.absolute(file));
    if (parsed is! ParsedLibraryResult) continue;
    final named = _Names(names);
    for (final unit in parsed.units) {
      unit.unit.accept(named);
    }
    if (named.found.isEmpty) continue;
    final resolved = await host.resolve(host.absolute(file));
    errors.addAll(host.errors(resolved));
    for (final unit in resolved.units) {
      final path = host.relative(unit.path);
      final named = _Names(names);
      unit.unit.accept(named);
      for (final name in named.found) {
        if (!_isGoRouters(name)) continue;
        final method = name.thisOrAncestorOfType<MethodDeclaration>();
        if (exempt(path, method?.name.lexeme)) continue;
        final line = unit.lineInfo.getLocation(name.offset).lineNumber;
        found.add('$path:$line: ${name.name} $why');
      }
    }
  }
  return [...errors, ...found];
}

class _Names extends RecursiveAstVisitor<void> {
  _Names(this.names);

  final Set<String> names;
  final found = <SimpleIdentifier>[];

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (names.contains(node.name)) found.add(node);
    super.visitSimpleIdentifier(node);
  }
}

/// Whether [name] is go_router's own on a router, on its delegate, or on
/// a context.
bool _isGoRouters(SimpleIdentifier name) {
  final element = name.element?.baseElement;
  if (element is! MethodElement) return false;
  final owner = element.enclosingElement;
  return element.library.uri.toString().startsWith('package:go_router/') &&
      (owner is ClassElement &&
              (owner.name == 'GoRouter' || owner.name == 'GoRouterDelegate') ||
          owner is ExtensionElement && owner.name == 'GoRouterHelper');
}
