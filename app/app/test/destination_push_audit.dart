/// A destination the chrome lists is reached with `go`, never a push.
///
/// A push of an in-shell location merges into whichever branch is on
/// screen, so a destination of its own pushed from a domain is filed
/// inside that domain's tab: tapping the tab later restores the wrong
/// page. Nothing in the compiler says so. This reads every library of
/// `lib/` that calls `push`, `pushInShell` or `pushOnce` on a `GoRouter`
/// or a `BuildContext`, and fails one whose location can evaluate to what
/// the chrome owns: a `WaxRoute` member `WaxNavTarget` is declared from,
/// the uploads list, or a review entry; or a `WaxNavTarget`'s `location`.
///
/// A location is followed through parentheses, casts, `!`, a conditional,
/// a `??`, a switch expression, a `WaxRoute` helper call, a local, field
/// or top-level variable (its initializer and every assignment), a
/// function, method or getter of this package (what it returns), an
/// interpolation or `+` that starts with one (unless the next text goes
/// beneath it with a `/`, which is a drill-in), a parameter of a local or
/// private function (the arguments at its calls in this library), a
/// variable a pattern binds whole (`final entry?`: what was matched), and
/// the call of a closure or of a torn-off function (what it returns, the
/// function read through the variables, getters and calls that hand it
/// over), whether called directly or through its `call`, null-aware or
/// not, or with `call` torn off. A library the scan resolves that does
/// not compile fails too.
///
/// What still stops the scan: a location read from a collection or
/// awaited; a field set through a constructor (`this.x` or an initializer
/// list); a variable a pattern binds part of; the parameter of a public
/// function or of a closure, and a parameter's default value; a function
/// handed on as a value, whose calls through it are not joined to its
/// parameters; anything from outside the package. `replace` and
/// `pushReplacement` file a match into the branch on screen the way `push`
/// does, and are not looked at.
library;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'analysis_host.dart';

const _routes = 'package:waxdeck/src/shell/routes.dart';

/// The rule on `lib/` and on fixtures, over the host [host] returns.
void destinationPushAudit(AnalysisHost Function() host) {
  test('nothing pushes a location the chrome owns', () async {
    final found = await _pushesIn(host(), libFiles(host()));
    expect(
      found,
      isEmpty,
      reason:
          'A destination the chrome lists, the uploads list and a review '
          'entry are reached with go, which files them in the branch that '
          'declares them.\n\n${found.join('\n')}',
    );
  });

  group('the destination push check', () {
    const preamble = '''
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck/src/music/music_controllers.dart';
import 'package:waxdeck/src/shell/adaptive_shell.dart';
import 'package:waxdeck/src/shell/routes.dart';

''';

    /// The line of the file [check] writes for [source] that holds [text].
    int lineOf(String source, String text) =>
        '$preamble$source'.split('\n').indexWhere((l) => l.contains(text)) + 1;

    var count = 0;
    Future<List<String>> check(String source, {bool compiles = true}) async {
      final path = 'lib/destination_push_fixture${count++}/a.dart';
      host().write(path, '$preamble$source');
      if (compiles) {
        final unit = await host().session.getResolvedUnit(
          host().absolute(path),
        );
        expect(
          (unit as ResolvedUnitResult).diagnostics.where(
            (diagnostic) => diagnostic.severity == Severity.error,
          ),
          isEmpty,
          reason: '$path does not compile',
        );
      }
      return _pushesIn(host(), [path]);
    }

    test('knows what the chrome owns from its declaration', () async {
      expect(
        await _ownedLocations(host()),
        containsAll(<String>[
          'home',
          'music',
          'podcasts',
          'books',
          'radio',
          'tasks',
          'review',
          'notifications',
          'settings',
          'admin',
          'stats',
          'downloads',
          'playlists',
          'musicTracks',
          'musicIndex',
          'bookIndex',
          'uploads',
          'reviewEntry',
        ]),
      );
    });

    test('reports each method on either receiver, and a location given '
        'directly', () async {
      final found = await check('''
void doors(GoRouter router, BuildContext context, String id) {
  router.push<void>(WaxRoute.tasks);
  context.push<void>(WaxRoute.uploads);
  router.pushInShell<void>(WaxRoute.tasks);
  router.pushOnce(WaxRoute.uploads);
  context.pushOnce(WaxRoute.tasks);
  context.push(WaxNavTarget.settings.location);
  router.push(WaxRoute.musicIndex(MusicDimension.genres));
}
''');
      expect(found, hasLength(7));
      expect(found[0], contains('push is given WaxRoute.tasks'));
      expect(found[1], contains('push is given WaxRoute.uploads'));
      expect(found[2], contains('pushInShell is given WaxRoute.tasks'));
      expect(found[3], contains('pushOnce is given WaxRoute.uploads'));
      expect(found[4], contains('pushOnce is given WaxRoute.tasks'));
      expect(
        found[5],
        contains('push is given WaxNavTarget.settings.location'),
      );
      expect(found[6], contains('WaxRoute.musicIndex'));
    });

    test('reports a review entry through the WaxRoute helper', () async {
      final found = await check('''
void door(GoRouter router, String id) {
  router.push<void>(WaxRoute.reviewEntry(id));
  router.pushInShell<void>(WaxRoute.reviewEntry(id));
}
''');
      expect(found, hasLength(2));
      expect(found[0], contains('push is given WaxRoute.reviewEntry(id)'));
      expect(found[1], contains('pushInShell is given'));
    });

    test('reports one handed over through a local variable', () async {
      final found = await check('''
void doors(GoRouter router, BuildContext context, String id, bool a) {
  final where = WaxRoute.notifications;
  router.push(where);
  final entry = WaxRoute.reviewEntry(id);
  context.push(entry);
  var later = WaxRoute.book(id);
  later = WaxRoute.tasks;
  context.pushOnce(later);
  final either = a ? WaxRoute.book(id) : (WaxRoute.admin);
  router.pushInShell<void>(either);
  final fallback = id.isEmpty ? null : WaxRoute.nowPlaying;
  router.push(fallback ?? WaxRoute.stats);
}
''');
      expect(found, hasLength(5));
      expect(found[0], contains('push is given where: WaxRoute.notifications'));
      expect(found[1], contains('WaxRoute.reviewEntry'));
      expect(found[2], contains('WaxRoute.tasks'));
      expect(found[3], contains('WaxRoute.admin'));
      expect(found[4], contains('WaxRoute.stats'));
    });

    test('reports one a function, a getter or a field of the package '
        'hands over', () async {
      final found = await check('''
String _pick(String id) {
  if (id.isEmpty) return WaxRoute.admin;
  return WaxRoute.book(id);
}

String get _where => WaxRoute.settings;

const _field = WaxRoute.review;

String _byKind(int kind) => switch (kind) {
  0 => WaxRoute.book('bk-1'),
  _ => WaxRoute.tasks,
};

void doors(GoRouter router, String id) {
  router.push(_pick(id));
  router.push(_where);
  router.push(_field);
  router.push(_byKind(1));
}
''');
      expect(found, hasLength(4));
      expect(found[0], contains('WaxRoute.admin'));
      expect(found[1], contains('WaxRoute.settings'));
      expect(found[2], contains('WaxRoute.review'));
      expect(found[3], contains('WaxRoute.tasks'));
    });

    test('passes a drill-in, an overlay and a go', () async {
      expect(
        await check('''
void doors(GoRouter router, BuildContext context, String id) {
  router.push(WaxRoute.book(id));
  context.push(WaxRoute.metadata(id));
  router.pushInShell<void>(WaxRoute.nowPlaying);
  context.pushOnce(WaxRoute.queue);
  router.push(WaxRoute.musicBucket(MusicDimension.genres, 'jazz'));
  router.go(WaxRoute.tasks);
  context.go(WaxRoute.uploads);
  router.go(WaxNavTarget.tasks.location);
  final where = WaxRoute.reviewEntry(id);
  router.go(where);
}
'''),
        isEmpty,
      );
    });

    test('passes a push that is not a router\'s', () async {
      expect(
        await check('''
class Stack {
  void push(String location) {}
}

void door(Stack stack) => stack.push(WaxRoute.tasks);
'''),
        isEmpty,
      );
    });

    test('reports an interpolation or a sum that starts with one', () async {
      final found = await check('''
void doors(GoRouter router, BuildContext context, String id) {
  router.push('\${WaxRoute.tasks}?task=\$id');
  context.push('\${WaxRoute.review}#top');
  router.pushInShell<void>(WaxRoute.uploads + '?open=\$id');
  context.pushOnce('\${WaxNavTarget.settings.location}');
  final where = '\${WaxRoute.reviewEntry(id)}?tab=1';
  router.push(where);
  final both = '\${WaxRoute.admin}\$id';
  router.push(both);
}
''');
      expect(found, hasLength(6));
      expect(found[0], contains('WaxRoute.tasks'));
      expect(found[1], contains('WaxRoute.review'));
      expect(found[2], contains('WaxRoute.uploads'));
      expect(found[3], contains('WaxNavTarget.location'));
      expect(found[4], contains('WaxRoute.reviewEntry'));
      expect(found[5], contains('WaxRoute.admin'));
    });

    test('passes an interpolation or a sum that goes beneath one', () async {
      expect(
        await check('''
void doors(GoRouter router, BuildContext context, String id) {
  router.push('\${WaxRoute.books}/\$id');
  context.push(WaxRoute.books + '/' + id);
  router.push('\${WaxRoute.playlists}/\$id/edit');
  context.pushOnce('/tasks?task=\$id');
  final below = '\${WaxRoute.podcasts}/shows/\$id';
  router.push(below);
  router.push(WaxRoute.show(id));
  router.push(WaxRoute.musicBucket(MusicDimension.genres, id));
  router.push(WaxRoute.bookSeries(id));
}
'''),
        isEmpty,
      );
    });

    test('follows a location into the private or local function it is '
        'passed to', () async {
      final found = await check('''
void _open(GoRouter router, String location) => router.push(location);

void _openAt(GoRouter router, {required String where}) =>
    router.pushInShell<void>(where);

void _hop(GoRouter router, String hop) => _open(router, hop);

void _again(GoRouter router, String location) {
  router.push(location);
  if (location.isEmpty) _again(router, location);
}

class _Door {
  _Door(this.router);

  final GoRouter router;

  void _go(String location) => router.pushOnce(location);

  void press() => _go(WaxRoute.notifications);
}

void doors(GoRouter router, String id) {
  _open(router, WaxRoute.book(id));
  _open(router, WaxRoute.tasks);
  _openAt(router, where: WaxRoute.reviewEntry(id));
  _hop(router, WaxRoute.admin);
  _again(router, WaxRoute.stats);
  void local(String location) => router.push(location);
  local(WaxRoute.settings);
}
''');
      expect(found, hasLength(5));
      expect(found[0], contains('push is given location'));
      expect(found[0], contains('WaxRoute.tasks'));
      expect(found[0], contains('WaxRoute.admin'));
      expect(found[1], contains('pushInShell is given where'));
      expect(found[1], contains('WaxRoute.reviewEntry'));
      expect(found[2], contains('WaxRoute.stats'));
      expect(found[3], contains('pushOnce is given location'));
      expect(found[3], contains('WaxRoute.notifications'));
      expect(found[4], contains('WaxRoute.settings'));
    });

    test('names the line that hands a function an owned location', () async {
      const source = '''
void _open(GoRouter router, String location) => router.push(location);

void doors(GoRouter router) {
  _open(router, WaxRoute.tasks);
}
''';
      final found = await check(source);
      final line = lineOf(source, '_open(router, WaxRoute.tasks);');
      expect(found, hasLength(1));
      expect(found.single, contains('WaxRoute.tasks (passed at line $line)'));
    });

    test('follows a closure of this library to what it returns', () async {
      final found = await check('''
String Function(String)? _entryOf(int kind) => switch (kind) {
  0 => (id) => WaxRoute.book(id),
  1 => (id) => WaxRoute.reviewEntry(id),
  _ => null,
};

void _open(GoRouter router, String location) => router.push(location);

void Function(String)? rowTap(GoRouter router, int kind) =>
    switch (_entryOf(kind)) {
      final entry? => (id) => _open(router, entry(id)),
      null => null,
    };

void doors(GoRouter router, int kind, String id) {
  if (_entryOf(kind) case final entry?) router.push(entry(id));
  final tasks = () => WaxRoute.tasks;
  router.push(tasks());
  var later = () => WaxRoute.book(id);
  later = () => WaxRoute.admin;
  router.pushOnce(later());
  router.push((() => WaxRoute.settings)());
  final pick = WaxRoute.notifications;
  router.pushInShell<void>(id.isEmpty ? pick : tasks());
  final open = WaxRoute.reviewEntry;
  router.push(open(id));
}
''');
      expect(found, hasLength(7));
      expect(found[0], contains('push is given location'));
      expect(found[0], contains('WaxRoute.reviewEntry'));
      expect(found[1], contains('push is given entry(id)'));
      expect(found[1], contains('WaxRoute.reviewEntry'));
      expect(found[2], contains('WaxRoute.tasks'));
      expect(found[3], contains('WaxRoute.admin'));
      expect(found[4], contains('WaxRoute.settings'));
      expect(found[5], contains('WaxRoute.notifications'));
      expect(found[5], contains('WaxRoute.tasks'));
      expect(found[6], contains('WaxRoute.reviewEntry'));
    });

    test('follows a closure called through call, null-aware or not, or torn '
        'off by it', () async {
      final found = await check('''
String Function(String)? _entryOf(int kind) => switch (kind) {
  1 => (id) => WaxRoute.reviewEntry(id),
  _ => null,
};

void doors(GoRouter router, int kind, String id) {
  final entry = _entryOf(kind);
  final maybe = entry?.call(id);
  if (maybe != null) router.push(maybe);
  if (entry != null) router.push(entry.call(id));
  router.pushInShell<void>((entry ?? (_) => WaxRoute.tasks).call(id));
  final torn = entry!.call;
  router.pushOnce(torn(id));
}
''');
      expect(found, hasLength(4));
      expect(found[0], contains('push is given maybe'));
      expect(found[0], contains('WaxRoute.reviewEntry'));
      expect(found[1], contains('push is given entry.call(id)'));
      expect(found[2], contains('WaxRoute.reviewEntry'));
      expect(found[2], contains('WaxRoute.tasks'));
      expect(found[3], contains('pushOnce is given torn(id)'));
    });

    test('passes a closure that builds a drill-in', () async {
      expect(
        await check('''
String Function(String)? _entryOf(int kind) => switch (kind) {
  0 => (id) => WaxRoute.book(id),
  1 => WaxRoute.bookSeries,
  _ => null,
};

void _open(GoRouter router, String location) => router.push(location);

void doors(GoRouter router, int kind, String id) {
  switch (_entryOf(kind)) {
    case final entry?:
      _open(router, entry(id));
  }
  final show = () => WaxRoute.show(id);
  router.push(show());
}
'''),
        isEmpty,
      );
    });

    test('does not read a location a public function is given', () async {
      expect(
        await check('''
void open(GoRouter router, String location) => router.push(location);

void doors(GoRouter router) => open(router, WaxRoute.tasks);
'''),
        isEmpty,
      );
    });

    test('does not read a location a function used as a value is '
        'given', () async {
      expect(
        await check('''
void _open(GoRouter router, String location) => router.push(location);

void _use(void Function(GoRouter, String) call, GoRouter router) {
  call(router, WaxRoute.tasks);
}

void doors(GoRouter router) => _use(_open, router);
'''),
        isEmpty,
      );
    });

    test('a library that does not compile fails on its first error', () async {
      expect(
        await check(
          'void open(GoRouter router) => router.push(missing);',
          compiles: false,
        ),
        [
          allOf(
            startsWith('lib/destination_push_fixture'),
            contains('missing'),
            endsWith('(an audit cannot read code that does not compile)'),
          ),
        ],
      );
    });
  });
}

/// The `WaxRoute` members the chrome's destinations are declared from, and
/// the two doors nothing declares: the uploads list and a review entry.
Future<Set<String>> _ownedLocations(AnalysisHost host) async {
  final resolved = await host.resolve(
    host.absolute('lib/src/shell/adaptive_shell.dart'),
  );
  final names = <String>{'uploads', 'reviewEntry'};
  for (final unit in resolved.units) {
    unit.unit.accept(_Declarations(names));
  }
  return names;
}

/// The `WaxRoute` members `WaxNavTarget` is declared from: its constants'
/// arguments, and what its `location` getter builds.
class _Declarations extends RecursiveAstVisitor<void> {
  _Declarations(this.names);

  final Set<String> names;

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    if (node.namePart.typeName.lexeme != 'WaxNavTarget') return;
    final refs = _WaxRouteRefs(names);
    for (final constant in node.body.constants) {
      constant.arguments?.accept(refs);
    }
    for (final member in node.body.members) {
      if (member is MethodDeclaration && member.name.lexeme == 'location') {
        member.body.accept(refs);
      }
    }
  }
}

class _WaxRouteRefs extends RecursiveAstVisitor<void> {
  _WaxRouteRefs(this.names);

  final Set<String> names;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element?.baseElement case final element?
        when _isWaxRouteMember(element)) {
      names.add(element.displayName);
    }
  }
}

bool _isWaxRouteMember(Element element) {
  final owner = element.enclosingElement;
  return owner is ClassElement &&
      owner.name == 'WaxRoute' &&
      owner.library.uri.toString() == _routes;
}

/// One line per push whose location [files] can evaluate to what the
/// chrome owns, after one per unit, of a library resolved for it, that
/// does not compile. Only a library that calls a push is resolved.
Future<List<String>> _pushesIn(
  AnalysisHost host,
  Iterable<String> files,
) async {
  final follow = _Follow(host, await _ownedLocations(host));
  final errors = <String>[];
  final found = <String>[];
  for (final file in files) {
    final parsed = host.session.getParsedLibrary(host.absolute(file));
    if (parsed is! ParsedLibraryResult) continue;
    final calls = _Calls();
    for (final unit in parsed.units) {
      unit.unit.accept(calls);
    }
    if (calls.found.isEmpty) continue;
    final resolved = await host.resolve(host.absolute(file));
    errors.addAll(host.errors(resolved));
    for (final unit in resolved.units) {
      final calls = _Calls();
      unit.unit.accept(calls);
      for (final call in calls.found) {
        if (!_isPush(call)) continue;
        final location = call.argumentList.arguments
            .where((argument) => argument is! NamedArgument)
            .firstOrNull
            ?.argumentExpression;
        if (location == null) continue;
        final line = unit.lineInfo.getLocation(call.offset).lineNumber;
        final owners = await follow.owners(location);
        if (owners.isEmpty) continue;
        found.add(
          '${host.relative(unit.path)}:$line: ${call.methodName.name} is '
          'given ${location.toSource()}: ${owners.join(', ')} is a location '
          'the chrome owns, so it is gone to, not pushed (a push files it '
          'inside the tab on screen)',
        );
      }
    }
  }
  return [...errors, ...found];
}

const _pushes = {'push', 'pushInShell', 'pushOnce'};

class _Calls extends RecursiveAstVisitor<void> {
  final found = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_pushes.contains(node.methodName.name)) found.add(node);
    super.visitMethodInvocation(node);
  }
}

/// Whether [call] is go_router's `push` on a router or a context, or the
/// app's `pushInShell` and `pushOnce`, which push the same way.
bool _isPush(MethodInvocation call) {
  final element = call.methodName.element?.baseElement;
  if (element is! MethodElement) return false;
  final owner = element.enclosingElement;
  final uri = element.library.uri.toString();
  return switch (call.methodName.name) {
    'push' =>
      uri.startsWith('package:go_router/') &&
          (owner is ClassElement && owner.name == 'GoRouter' ||
              owner is ExtensionElement && owner.name == 'GoRouterHelper'),
    'pushInShell' || 'pushOnce' => uri == _routes,
    _ => false,
  };
}

/// What an expression can evaluate to, read through the package.
class _Follow {
  _Follow(this.host, this.owned);

  final AnalysisHost host;
  final Set<String> owned;
  final _indexes = <Uri, Future<Map<Element, List<Expression>>>>{};

  /// The owned locations [expression] can evaluate to, each as it is
  /// written in `WaxRoute`.
  Future<Set<String>> owners(Expression expression) async {
    final walk = _Walk(this);
    await walk.visit(expression);
    return walk.found;
  }

  /// How [element] reads when it is one of the owned names: the member of
  /// `WaxRoute` it is, or a `WaxNavTarget`'s `location`.
  String? _owner(Element element) {
    final owner = element.enclosingElement;
    if (owner is ClassElement &&
        owner.name == 'WaxRoute' &&
        element.library?.uri.toString() == _routes &&
        owned.contains(element.displayName)) {
      return 'WaxRoute.${element.displayName}';
    }
    if (owner is EnumElement &&
        owner.name == 'WaxNavTarget' &&
        element.displayName == 'location') {
      return 'WaxNavTarget.location';
    }
    return null;
  }

  /// What this package says [element] holds: a variable's initializer and
  /// assignments, and what a function, method or getter returns.
  Future<List<Expression>> _valuesOf(Element element) async {
    final library = element.library;
    if (library == null ||
        !library.uri.toString().startsWith('package:waxdeck/')) {
      return const [];
    }
    if (element is FormalParameterElement && !_callersKnown(element)) {
      return const [];
    }
    final index = await (_indexes[library.uri] ??= _index(library));
    return index[element] ??
        (element is PropertyAccessorElement ? index[element.variable] : null) ??
        const [];
  }

  /// Whether every call of the function [parameter] belongs to is in its
  /// own library: a local function, or one whose name is private.
  bool _callersKnown(FormalParameterElement parameter) =>
      switch (parameter.enclosingElement) {
        LocalFunctionElement() => true,
        final ExecutableElement function => function.isPrivate,
        _ => false,
      };

  Future<Map<Element, List<Expression>>> _index(LibraryElement library) async {
    final resolved = await host.resolve(library.firstFragment.source.fullName);
    final index = <Element, List<Expression>>{};
    for (final unit in resolved.units) {
      unit.unit.accept(_Values(index));
    }
    return index;
  }
}

/// One evaluation: the owned locations found so far, and the elements
/// already read so a variable that feeds itself is read once.
class _Walk {
  _Walk(this.follow);

  final _Follow follow;
  final found = <String>{};
  final _seen = <Element>{};

  /// The line of the call a parameter's value was read from.
  int? _at;

  Future<void> visit(Expression e) async {
    switch (e) {
      case ParenthesizedExpression(:final expression):
      case AsExpression(:final expression):
        await visit(expression);
      case PostfixExpression(:final operand)
          when e.operator.type == TokenType.BANG:
        await visit(operand);
      case ConditionalExpression(:final thenExpression, :final elseExpression):
        await visit(thenExpression);
        await visit(elseExpression);
      case BinaryExpression(:final leftOperand, :final rightOperand)
          when e.operator.type == TokenType.QUESTION_QUESTION:
        await visit(leftOperand);
        await visit(rightOperand);
      case SwitchExpression(:final cases):
        for (final c in cases) {
          await visit(c.expression);
        }
      case StringInterpolation(:final elements):
        await _leading(elements);
      case BinaryExpression(:final leftOperand, :final rightOperand)
          when e.operator.type == TokenType.PLUS:
        if (!_goesBeneath(rightOperand)) await visit(leftOperand);
      case MethodInvocation(:final target?, :final methodName)
          when _isCallOf(target, methodName):
        await _results(target);
      case MethodInvocation(:final methodName)
          when _isFunctionValue(methodName):
        await _results(methodName);
      case MethodInvocation(:final methodName):
        await _named(methodName);
      case FunctionExpressionInvocation(:final function):
        await _results(function);
      case SimpleIdentifier():
        await _named(e);
      case PrefixedIdentifier(:final identifier):
        await _named(identifier);
      case PropertyAccess(:final propertyName):
        await _named(propertyName);
    }
  }

  /// Whether [name] is the `call` of [target], a function: `entry.call` or
  /// `entry?.call`, which is calling it.
  static bool _isCallOf(Expression target, SimpleIdentifier name) =>
      name.name == 'call' && target.staticType is FunctionType;

  /// Whether [name], called, is a variable or getter holding a function
  /// rather than a function or method itself.
  static bool _isFunctionValue(SimpleIdentifier name) {
    final element = name.element?.baseElement;
    return element != null &&
        (element is! ExecutableElement || element is PropertyAccessorElement);
  }

  /// The functions read as values so far, so one that holds itself is
  /// read once.
  final _seenFunctions = <Element>{};

  /// What a call of [function] can return: what a closure of this package
  /// returns, a function or helper torn off, read through the variables,
  /// getters and calls that hand the function over.
  Future<void> _results(Expression function) async {
    switch (function) {
      case ParenthesizedExpression(:final expression):
      case AsExpression(:final expression):
        await _results(expression);
      case PostfixExpression(:final operand)
          when function.operator.type == TokenType.BANG:
        await _results(operand);
      case FunctionExpression(:final body):
        for (final value in _returns(body)) {
          await visit(value);
        }
      case ConditionalExpression(:final thenExpression, :final elseExpression):
        await _results(thenExpression);
        await _results(elseExpression);
      case BinaryExpression(:final leftOperand, :final rightOperand)
          when function.operator.type == TokenType.QUESTION_QUESTION:
        await _results(leftOperand);
        await _results(rightOperand);
      case SwitchExpression(:final cases):
        for (final c in cases) {
          await _results(c.expression);
        }
      // A call handing back a function: what that function returns.
      case MethodInvocation(:final methodName):
        await _functionsOf(methodName, called: true);
      case SimpleIdentifier():
        await _functionsOf(function, called: false);
      // A function's `call` torn off is the function.
      case PrefixedIdentifier(:final prefix, :final identifier)
          when _isCallOf(prefix, identifier):
        await _results(prefix);
      case PrefixedIdentifier(:final identifier):
        await _functionsOf(identifier, called: false);
      case PropertyAccess(:final target?, :final propertyName)
          when _isCallOf(target, propertyName):
        await _results(target);
      case PropertyAccess(:final propertyName):
        await _functionsOf(propertyName, called: false);
    }
  }

  /// What calling the function [name] stands for returns: called, the
  /// functions it returns; else a torn-off function's own returns, or the
  /// functions a variable or getter holds.
  Future<void> _functionsOf(
    SimpleIdentifier name, {
    required bool called,
  }) async {
    final element = name.element?.baseElement;
    if (element == null) return;
    final torn =
        !called &&
        element is ExecutableElement &&
        element is! PropertyAccessorElement;
    if (torn) {
      if (follow._owner(element) case final owner?) {
        found.add(_at == null ? owner : '$owner (passed at line $_at)');
        return;
      }
      // Its returns are what a call of it gives.
      await _named(name);
      return;
    }
    if (!_seenFunctions.add(element)) return;
    final passed = element is FormalParameterElement;
    for (final value in await follow._valuesOf(element)) {
      final outer = _at;
      if (passed) {
        final unit = value.thisOrAncestorOfType<CompilationUnit>();
        _at = unit?.lineInfo.getLocation(value.offset).lineNumber;
      }
      await _results(value);
      _at = outer;
    }
  }

  /// What an interpolation starts with is the location it builds, unless
  /// the text after it goes beneath it: `'${WaxRoute.tasks}?task=$id'` is
  /// the tasks screen, `'${WaxRoute.books}/$id'` is one book.
  Future<void> _leading(List<InterpolationElement> elements) async {
    final start = elements.indexWhere(
      (element) => element is! InterpolationString || element.value.isNotEmpty,
    );
    if (start < 0) return;
    if (elements[start] case InterpolationExpression(:final expression)) {
      final after = elements.elementAtOrNull(start + 1);
      if (after is InterpolationString && after.value.startsWith('/')) return;
      await visit(expression);
    }
  }

  /// Whether [text], what a `+` appends, opens with a path segment.
  bool _goesBeneath(Expression text) => switch (text) {
    ParenthesizedExpression(:final expression) => _goesBeneath(expression),
    SimpleStringLiteral(:final value) => value.startsWith('/'),
    StringInterpolation(:final firstString) => firstString.value.startsWith(
      '/',
    ),
    _ => false,
  };

  Future<void> _named(SimpleIdentifier name) async {
    final element = name.element?.baseElement;
    if (element == null) return;
    if (follow._owner(element) case final owner?) {
      found.add(_at == null ? owner : '$owner (passed at line $_at)');
      return;
    }
    if (!_seen.add(element)) return;
    final passed = element is FormalParameterElement;
    for (final value in await follow._valuesOf(element)) {
      final outer = _at;
      if (passed) {
        final unit = value.thisOrAncestorOfType<CompilationUnit>();
        _at = unit?.lineInfo.getLocation(value.offset).lineNumber;
      }
      await visit(value);
      _at = outer;
    }
  }
}

/// What each variable is given, each function returns and each parameter is
/// passed, in one unit.
class _Values extends RecursiveAstVisitor<void> {
  _Values(this.index);

  final Map<Element, List<Expression>> index;

  void _add(Element? element, Iterable<Expression> values) {
    if (element != null) (index[element.baseElement] ??= []).addAll(values);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.initializer case final initializer?) {
      _add(node.declaredFragment?.element, [initializer]);
    }
    super.visitVariableDeclaration(node);
  }

  /// A variable a pattern binds holds what the pattern matched, where
  /// the pattern is that value whole: `final entry?` in a switch or an
  /// if-case, not one field of it.
  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    if (_matched(node) case final value?) {
      _add(node.declaredFragment?.element, [value]);
    }
    super.visitDeclaredVariablePattern(node);
  }

  static Expression? _matched(DartPattern pattern) {
    var at = pattern.parent;
    while (at is NullCheckPattern ||
        at is NullAssertPattern ||
        at is CastPattern ||
        at is ParenthesizedPattern) {
      at = at!.parent;
    }
    final matched = switch (at) {
      GuardedPattern(:final parent) => parent,
      PatternVariableDeclaration(:final expression) => expression,
      _ => null,
    };
    return switch (matched) {
      final Expression value => value,
      SwitchExpressionCase(:final parent?) when parent is SwitchExpression =>
        parent.expression,
      SwitchPatternCase(:final parent?) when parent is SwitchStatement =>
        parent.expression,
      CaseClause(:final parent?) => switch (parent) {
        IfStatement(:final expression) => expression,
        IfElement(:final expression) => expression,
        _ => null,
      },
      _ => null,
    };
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    if (node.operator.type == TokenType.EQ) {
      final written = node.writeElement;
      _add(written is PropertyAccessorElement ? written.variable : written, [
        node.rightHandSide,
      ]);
    }
    super.visitAssignmentExpression(node);
  }

  @override
  void visitArgumentList(ArgumentList node) {
    for (final argument in node.arguments) {
      _add(argument.correspondingParameter, [argument.argumentExpression]);
    }
    super.visitArgumentList(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _add(
      node.declaredFragment?.element,
      _returns(node.functionExpression.body),
    );
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _add(node.declaredFragment?.element, _returns(node.body));
    super.visitMethodDeclaration(node);
  }
}

/// What [body] returns, outside the closures and functions in it.
Iterable<Expression> _returns(FunctionBody body) => switch (body) {
  ExpressionFunctionBody(:final expression) => [expression],
  BlockFunctionBody() => (_Returns()..visitBlockFunctionBody(body)).found,
  _ => const [],
};

class _Returns extends RecursiveAstVisitor<void> {
  final found = <Expression>[];

  @override
  void visitReturnStatement(ReturnStatement node) {
    if (node.expression case final expression?) found.add(expression);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {}
}
