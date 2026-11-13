/// What an `add...` call registers goes to its `remove...` call as the same
/// object, or it is never removed. A tear-off of an extension or
/// extension-type instance member is a new closure each time, equal to no
/// other, so one handed to either leaks what it registers: it compiles and
/// analyzes clean. This reads every library of `lib/` that makes a call
/// whose method name starts with `add` or `remove`, and fails an argument
/// of one that can evaluate to such a tear-off (itself, or through a
/// conditional, a `??`, parentheses, a cast, a generic function reference).
/// One deeper in the argument, as what an inner call is given or in a
/// closure's body, is not what the call is handed.
/// A tear-off kept in a variable and handed over through it is one object
/// to both calls, which is the way to hand one over, so it is no breach. A
/// library it reads that does not compile fails too.
library;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'analysis_host.dart';

/// The rule on `lib/` and on fixtures, over the host [host] returns.
void extensionTearOffAudit(AnalysisHost Function() host) {
  test('nothing handed to an add or remove call is a tear-off of an '
      'extension member', () async {
    expect(await _tearOffsIn(host(), libFiles(host())), isEmpty);
  });

  group('the check', () {
    var count = 0;
    Future<List<String>> check(
      String source, {
      String? beside,
      bool compiles = true,
    }) async {
      final dir = 'lib/tear_off_fixture${count++}';
      final paths = ['$dir/a.dart', if (beside != null) '$dir/b.dart'];
      const foundation = "import 'package:flutter/foundation.dart';\n";
      host().write(
        paths.first,
        "$foundation${beside == null ? '' : "import 'b.dart';\n"}\n$source",
      );
      if (beside != null) host().write(paths.last, '$foundation\n$beside');
      for (final path in compiles ? paths : const <String>[]) {
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
      return _tearOffsIn(host(), paths);
    }

    test('reports an extension member handed to either', () async {
      final found = await check('''
class Clock extends ChangeNotifier {}

class Session {
  Session(this.clock);
  final Clock clock;

  void open() => clock.addListener(_tick);
  void close() => clock.removeListener(_tick);
}

extension _Ticks on Session {
  void _tick() {}
}
''');
      expect(found, hasLength(2));
      expect(found[0], contains('addListener is handed _tick'));
      expect(found[1], contains('removeListener is handed _tick'));
    });

    test('reports one anywhere in an argument of any add or remove call, '
        'from a library that declares no extension', () async {
      expect(
        await check(
          '''
class Router {
  void addRoute(void Function() route) {}
  void removeRoute(void Function() route) {}
}

void handle(Router router, Session session, Id id, void Function()? other) {
  router
    ..addRoute(other == null ? session.tick : other)
    ..addRoute(other ?? session.tick)
    ..addRoute((session.tick))
    ..addRoute(session.tick as dynamic)
    ..removeRoute(session.tock<int>)
    ..removeRoute(id.stamp);
}
''',
          beside: '''
class Session {}

extension Ticks on Session {
  void tick() {}
  void tock<T>() {}
}

extension type Id(int value) {
  void stamp() {}
}
''',
        ),
        [
          contains(
            'addRoute is handed session.tick, a tear-off of an '
            'extension member',
          ),
          contains('addRoute is handed session.tick,'),
          contains('addRoute is handed session.tick,'),
          contains('addRoute is handed session.tick,'),
          contains('removeRoute is handed session.tock<int>,'),
          contains(
            'removeRoute is handed id.stamp, a tear-off of an '
            'extension type member',
          ),
        ],
      );
    });

    test('passes an instance method, a mixin method, a closure and a static '
        'function, an extension\'s included', () async {
      expect(
        await check('''
mixin Ticks {
  void tock() {}
}

void tack() {}

class Clock extends ChangeNotifier {}

class Session with Ticks {
  Session(this.clock);
  final Clock clock;

  void open() {
    clock
      ..addListener(_tick)
      ..addListener(tock)
      ..addListener(() {})
      ..addListener(_tack)
      ..addListener(tack)
      ..addListener(Closing.stamp);
  }

  void _tick() {}
  static void _tack() {}
}

extension Closing on Session {
  static void stamp() {}

  void close() => clock.removeListener(_tick);
}
'''),
        isEmpty,
      );
    });

    test('passes one an inner call is given, and one in a closure', () async {
      expect(
        await check('''
class Clock extends ChangeNotifier {
  Object every(void Function() beat) => beat;
}

class Session {
  Session(this.clock);
  final Clock clock;
  final beats = <Object>[];

  void open() {
    beats.add(clock.every(_tick));
    clock.addListener(() => clock.every(_tick));
  }
}

extension _Ticks on Session {
  void _tick() {}
}
'''),
        isEmpty,
      );
    });

    test('passes an extension member kept in a variable and handed over '
        'through it', () async {
      expect(
        await check('''
class Clock extends ChangeNotifier {}

class Session {
  Session(this.clock);
  final Clock clock;
  late final VoidCallback _listener = _tick;

  void open() => clock.addListener(_listener);
  void close() => clock.removeListener(_listener);
}

extension _Ticks on Session {
  void _tick() {}
}
'''),
        isEmpty,
      );
    });

    test('a library that does not compile fails on its first error', () async {
      expect(
        await check(
          'void open(ChangeNotifier clock) => clock.addListener(missing);',
          compiles: false,
        ),
        [
          allOf(
            startsWith('lib/tear_off_fixture'),
            contains('missing'),
            endsWith('(an audit cannot read code that does not compile)'),
          ),
        ],
      );
    });
  });
}

/// One line per tear-off of an extension or extension-type instance member
/// that [files] hand to a call whose method name starts with `add` or
/// `remove`, after one per unit, of a library resolved for it, that does
/// not compile. Only a library that makes such a call is resolved.
Future<List<String>> _tearOffsIn(
  AnalysisHost host,
  Iterable<String> files,
) async {
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
        for (final argument in call.argumentList.arguments) {
          for (final (handed, owner) in _handedOver(
            argument.argumentExpression,
          )) {
            final line = unit.lineInfo.getLocation(handed.offset).lineNumber;
            found.add(
              '${host.relative(unit.path)}:$line: ${call.methodName.name} is '
              'handed ${handed.toSource()}, a tear-off of an $owner member, '
              'which equals no other tear-off of it',
            );
          }
        }
      }
    }
  }
  return [...errors, ...found];
}

class _Calls extends RecursiveAstVisitor<void> {
  final found = <MethodInvocation>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    if (name.startsWith('add') || name.startsWith('remove')) found.add(node);
    super.visitMethodInvocation(node);
  }
}

/// The tear-offs of extension and extension-type instance members that
/// [argument] can evaluate to, each with the kind of what declares it.
Iterable<(Expression, String)> _handedOver(Expression argument) sync* {
  switch (argument) {
    case ParenthesizedExpression(:final expression):
    case AsExpression(:final expression):
      yield* _handedOver(expression);
    case ConditionalExpression(:final thenExpression, :final elseExpression):
      yield* _handedOver(thenExpression);
      yield* _handedOver(elseExpression);
    case BinaryExpression(:final leftOperand, :final rightOperand)
        when argument.operator.type == TokenType.QUESTION_QUESTION:
      yield* _handedOver(leftOperand);
      yield* _handedOver(rightOperand);
    case FunctionReference(:final function):
      for (final (_, owner) in _handedOver(function)) {
        yield (argument, owner);
      }
    case SimpleIdentifier():
      if (_owner(argument) case final owner?) yield (argument, owner);
    case PrefixedIdentifier(:final identifier):
      if (_owner(identifier) case final owner?) yield (argument, owner);
    case PropertyAccess(:final propertyName):
      if (_owner(propertyName) case final owner?) yield (argument, owner);
  }
}

/// What declares the instance method [name] tears off, when that is an
/// extension or an extension type.
String? _owner(SimpleIdentifier name) {
  final element = name.element?.baseElement;
  if (element is! MethodElement || element.isStatic) return null;
  return switch (element.enclosingElement) {
    ExtensionTypeElement() => 'extension type',
    ExtensionElement() => 'extension',
    _ => null,
  };
}
