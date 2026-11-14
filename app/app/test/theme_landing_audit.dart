/// A theme switch lands in one frame, and two framework widgets keep it from
/// doing so unless every site says what it does about them: a `Material`
/// eases its default text style, its shadow and its shape into the new
/// theme over its `animationDuration`, and a `Scaffold`'s own Material does
/// the same for its body with no duration to pass, so a Text that inherits
/// its colour draws the old theme's ink first. Nothing in the compiler or
/// the analyzer says so, and a site added without either goes unseen.
///
/// This reads every library of `lib/` here and of `waxdeck_ui`'s `lib/`
/// whose source names `Material` or `Scaffold`, and fails
///
///  * a `Material` of `material_ui` created without an `animationDuration`
///    argument (zero where it animates nothing on purpose, and inside
///    `waxdeck_ui` the duration `WaxThemeLanding` hands its builder where it
///    animates a state change), and
///  * a `Scaffold` of `material_ui` created without a `body` argument whose
///    outermost widget, parentheses aside, is `WaxPlainTextStyle`. Only the
///    body is read: an app bar or a floating button the Scaffold places
///    under its Material is the caller's to hold still.
///
/// A site is exempt only when [_exempt] names it, with the reason. The key is
/// the widget, the library's path from the app package and the class and
/// member that hold the site (`Material ../packages/x/lib/y.dart#Card.build`),
/// and it covers every site of that widget there. An exemption that matches
/// no breach fails too, so the map cannot rot. A library it reads that does
/// not compile fails.
///
/// What it reads: an instance creation, with or without `new` or `const`,
/// whose type resolves to those classes, through any import prefix or
/// typedef that names them in a library the scan reads. A library reaching
/// them only through a typedef declared elsewhere is not read, nor is a
/// constructor tear-off. Nor is a framework widget that builds a Material of
/// its own (a dialog, a card, a snack bar, an app bar): it guards direct
/// creations only.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'analysis_host.dart';

/// The rule on `lib/`, on `waxdeck_ui`'s `lib/` and on fixtures, over the
/// host [host] returns.
void themeLandingAudit(AnalysisHost Function() host) {
  test('every Material says how long it animates and every Scaffold holds '
      'its body under WaxPlainTextStyle', () async {
    final breaches = await _breachesIn(host(), _libraries(host()), _exempt);
    expect(
      breaches,
      isEmpty,
      reason:
          'A theme switch must land in one frame. Pass animationDuration to '
          'every Material (Duration.zero where it animates nothing on '
          'purpose, and in waxdeck_ui the duration WaxThemeLanding hands its '
          'builder where it animates a state change), and put every Scaffold '
          'body under WaxPlainTextStyle, or name the site in _exempt with the '
          'reason.'
          '\n\n${breaches.join('\n')}',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('every exemption has a reason', () {
    expect(_exempt.entries.where((e) => e.value.trim().isEmpty), isEmpty);
  });

  group('the theme landing check', () {
    var count = 0;
    Future<List<String>> check(
      String source, {
      Map<String, String> exempt = const <String, String>{},
      bool compiles = true,
    }) async {
      final dir = 'lib/theme_landing_fixture${count++}';
      host().write(
        '$dir/a.dart',
        "import 'package:waxdeck_ui/waxdeck_ui.dart';\n\n$source",
      );
      final path = host().absolute('$dir/a.dart');
      if (compiles) {
        final unit = await host().session.getResolvedUnit(path);
        expect(
          (unit as ResolvedUnitResult).diagnostics.where(
            (diagnostic) => diagnostic.severity == Severity.error,
          ),
          isEmpty,
          reason: '$dir/a.dart does not compile',
        );
      }
      return _breachesIn(host(), [path], exempt);
    }

    test('reports a Material with no animationDuration, however it is '
        'written', () async {
      final found = await check('''
import 'package:waxdeck_ui/waxdeck_ui.dart' as ui;

typedef Sheet = Material;

class Plain extends StatelessWidget {
  const Plain({super.key});

  @override
  Widget build(BuildContext context) => const Material(child: SizedBox());
}

Widget prefixed() => ui.Material(child: const SizedBox());
Widget aliased() => Sheet(child: const SizedBox());
Widget keyword() => new Material(color: Colors.red);
''');
      expect(found, [
        allOf(contains('a.dart:11:'), contains('Material passes no')),
        allOf(contains('a.dart:14:'), contains('Material passes no')),
        allOf(contains('a.dart:15:'), contains('Material passes no')),
        allOf(contains('a.dart:16:'), contains('Material passes no')),
      ]);
    });

    test('passes a Material that gives one, zero or not', () async {
      expect(
        await check('''
Widget zero() =>
    const Material(animationDuration: Duration.zero, child: SizedBox());

Widget given(Duration duration) =>
    Material(animationDuration: duration, child: const SizedBox());
'''),
        isEmpty,
      );
    });

    test('reports a Scaffold with no body, or one that is not under '
        'WaxPlainTextStyle', () async {
      final found = await check('''
Widget none() => const Scaffold();

Widget bare() => const Scaffold(body: SizedBox());

Widget inner() => const Scaffold(
  body: Center(child: WaxPlainTextStyle(child: SizedBox())),
);

Widget chosen(bool a) => Scaffold(
  body: a
      ? const WaxPlainTextStyle(child: SizedBox())
      : const SizedBox(),
);
''');
      expect(found, [
        allOf(contains('a.dart:3:'), contains('Scaffold passes no body')),
        allOf(contains('a.dart:5:'), contains('SizedBox()')),
        allOf(contains('a.dart:7:'), contains('Center(')),
        allOf(contains('a.dart:11:'), contains('a ?')),
      ]);
    });

    test('passes a Scaffold whose body is a WaxPlainTextStyle, in '
        'parentheses too', () async {
      expect(
        await check('''
Widget plain() => const Scaffold(
  body: WaxPlainTextStyle(child: SizedBox()),
);

Widget wrapped() => const Scaffold(
  body: (WaxPlainTextStyle(child: SizedBox())),
);
'''),
        isEmpty,
      );
    });

    test('leaves alone a Material or a Scaffold of its own', () async {
      expect(
        await check('''
class Material {
  const Material({this.child});
  final Widget? child;
}

class Scaffold {
  const Scaffold();
}

Object own() => [const Material(child: SizedBox()), const Scaffold()];
'''),
        isEmpty,
      );
    });

    test('passes a site its exemption names, and no other', () async {
      final source = '''
class Row1 {
  Widget build() => const Material(child: SizedBox());
  Widget other() => const Scaffold();
}
''';
      final found = await check(
        source,
        exempt: {
          // `count` is the number the call below gives its fixture.
          'Material lib/theme_landing_fixture$count/a.dart#Row1.build':
              'draws nothing the theme can move',
        },
      );
      expect(found, [allOf(contains('Scaffold passes no body'))]);
    });

    test('fails an exemption that matches nothing', () async {
      final found = await check(
        'Widget fine() => const Material(animationDuration: Duration.zero);',
        exempt: {
          'Material lib/theme_landing_fixture$count/a.dart#fine': 'a reason',
        },
      );
      expect(found, [
        allOf(
          contains('Material lib/theme_landing_fixture'),
          contains('is exempt, but no site of it breaks the rule (any more)'),
        ),
      ]);
    });

    test('a library that does not compile fails on its first error', () async {
      expect(
        await check(
          'Widget broken() => '
          'Material(animationDuration: Duration.zero, child: missing);',
          compiles: false,
        ),
        [
          allOf(
            startsWith('lib/theme_landing_fixture'),
            contains('missing'),
            endsWith('(an audit cannot read code that does not compile)'),
          ),
        ],
      );
    });
  });
}

/// The Dart files of this package's `lib/` and of `waxdeck_ui`'s, absolute.
List<String> _libraries(AnalysisHost host) => [
  for (final file in libFiles(host)) host.absolute(file),
  for (final file in Directory(
    p.normalize(p.join(host.root, '..', 'packages', 'waxdeck_ui', 'lib')),
  ).listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart')) file.path,
]..sort();

/// Where the audit reads, as the host names paths: this package's `lib/`
/// and `waxdeck_ui`'s.
const _roots = ['lib/', '../packages/waxdeck_ui/lib/'];

/// Sites that need neither a duration nor a plain text style, each with
/// why. None today.
const Map<String, String> _exempt = <String, String>{};

/// One line per site of [files], absolute paths, that breaks the rule, and
/// one per unit of a library read that does not compile, then one per
/// exemption in [exempt] no site needs.
Future<List<String>> _breachesIn(
  AnalysisHost host,
  Iterable<String> files,
  Map<String, String> exempt,
) async {
  final errors = <String>[];
  final breaches = <String>[];
  final used = <String>{};
  for (final file in files) {
    final parsed = host.session.getParsedLibrary(file);
    if (parsed is! ParsedLibraryResult) continue;
    final names = _Names();
    for (final unit in parsed.units) {
      unit.unit.accept(names);
    }
    if (!names.found) continue;
    final resolved = await host.resolve(file);
    errors.addAll(host.errors(resolved, under: _roots));
    for (final unit in resolved.units) {
      final sites = _Sites();
      unit.unit.accept(sites);
      for (final (:node, :widget, :scope) in sites.found) {
        final breach = widget == 'Material'
            ? _durationBreach(node)
            : _bodyBreach(node);
        if (breach == null) continue;
        final path = host.relative(unit.path);
        final key = '$widget $path#$scope';
        if (exempt.containsKey(key)) {
          used.add(key);
          continue;
        }
        final line = unit.lineInfo.getLocation(node.offset).lineNumber;
        breaches.add('$path:$line: $breach');
      }
    }
  }
  for (final key in exempt.keys) {
    if (!used.contains(key)) {
      breaches.add(
        '$key is exempt, but no site of it breaks the rule (any more): drop '
        'the entry',
      );
    }
  }
  return [...errors, ...breaches];
}

String? _durationBreach(InstanceCreationExpression node) =>
    _argument(node, 'animationDuration') == null
    ? 'Material passes no animationDuration, so it eases its text style, '
          'shadow and shape into a new theme over 200 ms'
    : null;

String? _bodyBreach(InstanceCreationExpression node) {
  final body = _argument(node, 'body');
  if (body == null) return 'Scaffold passes no body';
  var outermost = body;
  while (outermost is ParenthesizedExpression) {
    outermost = outermost.expression;
  }
  if (outermost is InstanceCreationExpression &&
      _is(outermost.staticType, 'WaxPlainTextStyle', 'waxdeck_ui')) {
    return null;
  }
  final source = outermost.toSource().split('\n').first;
  final shown = source.length > 40 ? '${source.substring(0, 40)}...' : source;
  return 'Scaffold body starts with `$shown`, not WaxPlainTextStyle, so its '
      'Material eases the text style a bare Text inherits';
}

Expression? _argument(InstanceCreationExpression node, String name) {
  for (final argument in node.argumentList.arguments) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument.argumentExpression;
    }
  }
  return null;
}

/// Whether [type] is the class [name] of the package [package].
bool _is(DartType? type, String name, String package) {
  final element = type?.element;
  return element is InterfaceElement &&
      element.name == name &&
      element.library.uri.toString().startsWith('package:$package/');
}

/// Whether the parsed code names a widget the audit reads, which decides
/// whether the library is worth resolving.
class _Names extends RecursiveAstVisitor<void> {
  var found = false;

  static const _watched = {'Material', 'Scaffold'};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_watched.contains(node.methodName.name)) found = true;
    super.visitMethodInvocation(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (_watched.contains(node.name.lexeme)) found = true;
    super.visitNamedType(node);
  }
}

typedef _Site = ({
  InstanceCreationExpression node,
  String widget,
  String scope,
});

/// The creations of `Material` and `Scaffold` in resolved code, each with
/// the class and member that hold it.
class _Sites extends RecursiveAstVisitor<void> {
  final found = <_Site>[];
  final _scope = <String>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.staticType;
    for (final widget in const ['Material', 'Scaffold']) {
      if (_is(type, widget, 'material_ui')) {
        found.add((node: node, widget: widget, scope: _scope.join('.')));
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  void _within(String? name, void Function() visit) {
    if (name != null) _scope.add(name);
    visit();
    if (name != null) _scope.removeLast();
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) => _within(
    node.namePart.typeName.lexeme,
    () => super.visitClassDeclaration(node),
  );

  @override
  void visitMixinDeclaration(MixinDeclaration node) =>
      _within(node.name.lexeme, () => super.visitMixinDeclaration(node));

  @override
  void visitEnumDeclaration(EnumDeclaration node) => _within(
    node.namePart.typeName.lexeme,
    () => super.visitEnumDeclaration(node),
  );

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) =>
      _within(node.name?.lexeme, () => super.visitExtensionDeclaration(node));

  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) => _within(
    node.namePart.typeName.lexeme,
    () => super.visitExtensionTypeDeclaration(node),
  );

  @override
  void visitMethodDeclaration(MethodDeclaration node) =>
      _within(node.name.lexeme, () => super.visitMethodDeclaration(node));

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) => _within(
    node.parent is CompilationUnit ? node.name.lexeme : null,
    () => super.visitFunctionDeclaration(node),
  );
}
