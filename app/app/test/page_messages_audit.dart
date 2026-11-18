/// Every page draws the shell's messages.
///
/// Material's messenger drew its snack bar on every Scaffold it found. The
/// shell's bar is drawn by the pages that say they are pages: every
/// `WaxScaffold`, and a `ShellMessageArea` around a page on a bare
/// Scaffold. A page on a bare Scaffold without one draws no message, and
/// only a test that names that page would notice. Nothing in the compiler
/// says so. This reads every library of `lib/` that names `Scaffold` and
/// fails a `Scaffold` of `material_ui` that is not built inside a
/// `ShellMessageArea` or a `WaxScaffold`: in the same expression (a closure
/// handed to one included), or in a widget every one of whose creations in
/// `lib/` is, read up through the widgets that create those. A `State`'s
/// Scaffold is its widget's. One built in what a page opens over itself,
/// a dialog, a sheet, a menu (an argument of the framework's or the design
/// system's `show` functions, or of a popup route), is not a page and
/// passes: an area there would draw a second bar over the page's. A
/// library it reads that does not compile fails too.
///
/// What it cannot see: a page with no material `Scaffold` at all, either
/// none or another design-system scaffold (`CarModeScaffold`,
/// `PlayerScaffold`); `route_table_test.dart` catches those by asking
/// every location's screen for a place for messages. A widget created
/// only from outside `lib/` or through a constructor tear-off, which reads
/// as created nowhere and fails; a Scaffold built in a function rather
/// than a widget, read in its own expression only.
library;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'analysis_host.dart';

const _messages = 'package:waxdeck/src/shell/shell_messages.dart';

/// The rule on `lib/` and on fixtures, over the host [host] returns.
void pageMessagesAudit(AnalysisHost Function() host) {
  test("every page on a bare Scaffold draws the shell's messages", () async {
    final found = await _barePagesIn(host(), libFiles(host()));
    expect(
      found,
      isEmpty,
      reason:
          "The shell's messages are drawn by the pages that say they are "
          'pages: a WaxScaffold, or a ShellMessageArea around a page on a '
          'bare Scaffold. Build this page as one or the other.\n\n'
          '${found.join('\n')}',
    );
  });

  group('the page messages check', () {
    const preamble = '''
import 'package:flutter/widgets.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

''';

    /// The line of the file [check] writes for [source] that holds [text].
    int lineOf(String source, String text) =>
        '$preamble$source'.split('\n').indexWhere((l) => l.contains(text)) + 1;

    var count = 0;
    Future<(String, List<String>)> check(String source) async {
      final path = 'lib/page_messages_fixture${count++}/a.dart';
      host().write(path, '$preamble$source');
      final unit = await host().session.getResolvedUnit(host().absolute(path));
      expect(
        (unit as ResolvedUnitResult).diagnostics.where(
          (diagnostic) => diagnostic.severity == Severity.error,
        ),
        isEmpty,
        reason: '$path does not compile',
      );
      return (path, await _barePagesIn(host(), [path]));
    }

    test('reports a page planted on a bare Scaffold', () async {
      const source = '''
class PlantedPage extends StatelessWidget {
  const PlantedPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

Widget route() => const PlantedPage();
''';
      final (path, found) = await check(source);
      expect(found, [
        '$path:${lineOf(source, 'Scaffold(body')}: a Scaffold no '
            'ShellMessageArea or WaxScaffold holds, so no message is drawn '
            'on it: PlantedPage is created bare at '
            '$path:${lineOf(source, 'route()')}',
      ]);
    });

    test("reports a State's Scaffold, a widget created bare once, and one "
        'created nowhere', () async {
      const source = '''
class StatePage extends StatefulWidget {
  const StatePage({super.key});

  @override
  State<StatePage> createState() => _StatePageState();
}

class _StatePageState extends State<StatePage> {
  @override
  Widget build(BuildContext context) => const Scaffold();
}

class TwicePage extends StatelessWidget {
  const TwicePage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class NowherePage extends StatelessWidget {
  const NowherePage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}

Widget routes() => const Column(
  children: <Widget>[
    StatePage(),
    ShellMessageArea(child: TwicePage()),
    TwicePage(),
  ],
);
''';
      final (path, found) = await check(source);
      expect(found, hasLength(3));
      expect(
        found[0],
        endsWith(
          'StatePage is created bare at $path:${lineOf(source, '    '
          'StatePage(),')}',
        ),
      );
      expect(
        found[1],
        endsWith(
          'TwicePage is created bare at $path:${lineOf(source, '    '
          'TwicePage(),')}',
        ),
      );
      expect(found[2], endsWith('NowherePage is created nowhere in lib/'));
    });

    test('passes a Scaffold in a dialog, a sheet or a route a page opens '
        'over itself, none of which is a page', () async {
      final (_, found) = await check('''
class OpeningPage extends StatelessWidget {
  const OpeningPage({super.key});

  Future<void> _dialog(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const Scaffold(body: SizedBox()),
  );

  Future<void> _sheet(BuildContext context) => showWaxSheet<void>(
    context: context,
    builder: (context) => const SheetBody(),
  );

  Future<void> _route(BuildContext context) => Navigator.of(context).push(
    DialogRoute<void>(context: context, builder: (context) => const Scaffold()),
  );

  @override
  Widget build(BuildContext context) => WaxScaffold(
    title: 'Opening',
    body: GestureDetector(
      onTap: () {
        _dialog(context);
        _sheet(context);
        _route(context);
      },
    ),
  );
}

class SheetBody extends StatelessWidget {
  const SheetBody({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}

Widget route() => const OpeningPage();
''');
      expect(found, isEmpty);
    });

    test('passes a Scaffold in an area or a WaxScaffold, through a closure, '
        'or in a widget only ever created in one', () async {
      final (_, found) = await check('''
class AreaPage extends StatelessWidget {
  const AreaPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const ShellMessageArea(child: Scaffold());
}

class NestedPage extends StatelessWidget {
  const NestedPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const WaxScaffold(title: 'Nested', body: Scaffold());
}

class LaterPage extends StatelessWidget {
  const LaterPage({super.key});

  @override
  Widget build(BuildContext context) => ShellMessageArea(
    child: Builder(builder: (context) => const Scaffold()),
  );
}

class InnerTab extends StatelessWidget {
  const InnerTab({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}

class OuterPage extends StatelessWidget {
  const OuterPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const WaxScaffold(title: 'Outer', body: InnerTab());
}
''');
      expect(found, isEmpty);
    });
  });
}

/// One line per Scaffold of [files] no page holds, after one per unit, of
/// a library resolved for it, that does not compile.
Future<List<String>> _barePagesIn(
  AnalysisHost host,
  Iterable<String> files,
) async {
  final scan = _Scan(host, {...libFiles(host), ...files});
  final errors = <String>[];
  final found = <String>[];
  for (final file in files) {
    final library = await scan.libraryNaming(file, 'Scaffold');
    if (library == null) continue;
    errors.addAll(host.errors(library));
    for (final unit in library.units) {
      final scaffolds = _Creations(_isScaffold);
      unit.unit.accept(scaffolds);
      for (final node in scaffolds.found) {
        final bare = await scan.bare(node);
        if (bare.isEmpty) continue;
        final line = unit.lineInfo.getLocation(node.offset).lineNumber;
        found.add(
          '${host.relative(unit.path)}:$line: a Scaffold no ShellMessageArea '
          'or WaxScaffold holds, so no message is drawn on it: '
          '${bare.join('; ')}',
        );
      }
    }
  }
  return [...errors, ...found];
}

/// Where the widgets of the package are created, read once each.
class _Scan {
  _Scan(this.host, this.files);

  final AnalysisHost host;

  /// Every library a widget may be created in.
  final Set<String> files;

  /// Why each widget read so far is not always created inside a page.
  final _bareWidgets = <InterfaceElement, List<String>>{};

  /// The widgets being read, so one that creates itself is read once.
  final _reading = <InterfaceElement>{};

  /// The library at [file], resolved, if its source names [name].
  Future<ResolvedLibraryResult?> libraryNaming(String file, String name) {
    final parsed = host.session.getParsedLibrary(host.absolute(file));
    if (parsed is! ParsedLibraryResult) return Future.value();
    final word = RegExp('\\b${RegExp.escape(name)}\\b');
    if (!parsed.units.any((unit) => word.hasMatch(unit.content))) {
      return Future.value();
    }
    return host.resolve(host.absolute(file));
  }

  /// Why [node] is not built inside a page; empty when it is, or when it
  /// is in something a page opens over itself.
  Future<List<String>> bare(AstNode node) async {
    if (_inPage(node) || _inOverlay(node)) return const [];
    final widget = _widgetOf(node);
    if (widget == null) return const ['it is built outside any widget'];
    return _bareWidget(widget);
  }

  Future<List<String>> _bareWidget(InterfaceElement widget) async {
    if (_bareWidgets[widget] case final known?) return known;
    final name = widget.displayName;
    if (!_reading.add(widget)) return ['$name creates itself'];
    final why = <String>[];
    var created = 0;
    for (final file in files) {
      final library = await libraryNaming(file, name);
      if (library == null) continue;
      for (final unit in library.units) {
        final sites = _Creations((type) => type == widget);
        unit.unit.accept(sites);
        for (final site in sites.found) {
          created++;
          if ((await bare(site)).isEmpty) continue;
          final line = unit.lineInfo.getLocation(site.offset).lineNumber;
          why.add('$name is created bare at ${host.relative(unit.path)}:$line');
        }
      }
    }
    if (created == 0) why.add('$name is created nowhere in lib/');
    _reading.remove(widget);
    return _bareWidgets[widget] = why;
  }
}

/// Whether [node] is built in an argument of a page: a `ShellMessageArea`
/// or a `WaxScaffold`.
bool _inPage(AstNode node) {
  for (var at = node.parent; at != null; at = at.parent) {
    if (at is InstanceCreationExpression) {
      final type = at.staticType?.element;
      if (type is InterfaceElement &&
          (type.name == 'ShellMessageArea' &&
                  type.library.uri.toString() == _messages ||
              type.name == 'WaxScaffold' &&
                  type.library.uri.toString().startsWith(
                    'package:waxdeck_ui/',
                  ))) {
        return true;
      }
    }
  }
  return false;
}

/// Whether [node] is built in what a page opens over itself: an argument of
/// a `show` function of the framework or the design system that answers
/// later (`showDialog`, `showWaxSheet`, `showMenu`), or of a popup route.
bool _inOverlay(AstNode node) {
  for (var at = node.parent; at != null; at = at.parent) {
    if (at is MethodInvocation) {
      final shown = at.methodName.element;
      if (shown is ExecutableElement &&
          (shown.name ?? '').startsWith('show') &&
          _isFramework(shown.library.uri) &&
          shown.returnType.isDartAsyncFuture) {
        return true;
      }
    }
    if (at is InstanceCreationExpression) {
      final type = at.staticType;
      if (type is InterfaceType &&
          type.allSupertypes.any(
            (supertype) =>
                supertype.element.name == 'PopupRoute' &&
                _isFramework(supertype.element.library.uri),
          )) {
        return true;
      }
    }
  }
  return false;
}

/// Whether [library] is the framework's or the design system's.
bool _isFramework(Uri library) => const <String>[
  'package:flutter/',
  'package:material_ui/',
  'package:cupertino_ui/',
  'package:waxdeck_ui/',
].any(library.toString().startsWith);

/// The widget whose build holds [node]: its class's, or for a `State` the
/// widget it is the state of.
InterfaceElement? _widgetOf(AstNode node) {
  final element = node
      .thisOrAncestorOfType<ClassDeclaration>()
      ?.declaredFragment
      ?.element;
  if (element == null) return null;
  for (final type in element.allSupertypes) {
    if (type.element.name == 'State' &&
        type.element.library.uri.toString().startsWith('package:flutter/') &&
        type.typeArguments.isNotEmpty) {
      final widget = type.typeArguments.first.element;
      return widget is InterfaceElement ? widget : null;
    }
  }
  return element;
}

bool _isScaffold(InterfaceElement type) =>
    type.name == 'Scaffold' &&
    type.library.uri.toString().startsWith('package:material_ui/');

/// The creations, in resolved code, of a class [matches] accepts.
class _Creations extends RecursiveAstVisitor<void> {
  _Creations(this.matches);

  final bool Function(InterfaceElement type) matches;
  final found = <InstanceCreationExpression>[];

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.staticType?.element;
    if (type is InterfaceElement && matches(type)) found.add(node);
    super.visitInstanceCreationExpression(node);
  }
}
