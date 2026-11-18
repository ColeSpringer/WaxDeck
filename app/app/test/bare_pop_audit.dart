/// go_router's `pop` goes through `popPage`.
///
/// On web go_router reports a router pop as a new browser entry, so the
/// entry behind the one on screen is the page just closed, and back lands
/// on it. `popPage` hands the pop to the navigation history, which takes a
/// push off by the browser's own back instead. Nothing in the compiler
/// says so. This reads every library of `lib/` that names `pop` or
/// `popRoute` and fails one that calls or tears off go_router's own (on a
/// `GoRouter`, on its `GoRouterDelegate`, or through its `BuildContext`
/// extension) anywhere but in `popPage` itself and in the history, whose
/// router moves are its own.
///
/// What it cannot see: a `Navigator` pop, the navigators' own included
/// (`routerDelegate.navigatorKey.currentState!.pop()`), since a dialog's
/// cannot be told from a page's, so the pages that pop themselves through
/// one are read by hand; and a `popRoute` called on a delegate typed as
/// Flutter's `RouterDelegate`, which resolves to Flutter's method.
library;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

import 'analysis_host.dart';
import 'bare_replace_audit.dart';

const _routes = 'lib/src/shell/routes.dart';
const _history = 'lib/src/shell/navigation_history.dart';

/// The rule on `lib/` and on fixtures, over the host [host] returns.
void barePopAudit(AnalysisHost Function() host) {
  test('nothing pops a go_router page but popPage', () async {
    final found = await _popsIn(host(), libFiles(host()));
    expect(
      found,
      isEmpty,
      reason:
          'A router pop is a new browser entry, which back lands on; '
          'popPage takes a push off by the browser back.\n\n'
          '${found.join('\n')}',
    );
  });

  group('the bare pop check', () {
    var count = 0;
    Future<List<String>> check(String source) async {
      final path = 'lib/bare_pop_fixture${count++}/a.dart';
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
      return _popsIn(host(), [path]);
    }

    test('reports a call on either receiver or the delegate, and a '
        'tear-off', () async {
      final found = await check('''
void leaves(GoRouter router, BuildContext context) {
  router.pop<void>();
  context.pop(true);
  GoRouter.of(context).pop<String>('done');
  final later = context.pop;
  later();
  router.routerDelegate.pop<void>();
  router.routerDelegate.popRoute();
}
''');
      expect(found, hasLength(6));
      expect(found[0], contains('a.dart:6: pop'));
      expect(found[1], contains('a.dart:7: pop'));
      expect(found[2], contains('a.dart:8: pop'));
      expect(found[3], contains('a.dart:9: pop'));
      expect(found[4], contains('a.dart:11: pop'));
      expect(found[5], contains('a.dart:12: popRoute'));
    });

    test('leaves popPage and every other pop alone', () async {
      final found = await check('''
class Stack {
  void pop() {}
}

void leaves(GoRouter router, BuildContext context, Stack stack) {
  router.popPage(true);
  router.leave();
  Navigator.of(context).pop();
  Navigator.pop(context);
  stack.pop();
}
''');
      expect(found, isEmpty);
    });

    test('exempts only popPage in routes.dart', () async {
      final found = await check('''
extension on GoRouter {
  void popPage() => pop<void>();
}
''');
      expect(found, hasLength(1));
      expect(found.single, contains('a.dart:6: pop'));
    });
  });
}

Future<List<String>> _popsIn(AnalysisHost host, Iterable<String> files) =>
    goRoutersOwnIn(
      host,
      files,
      names: const {'pop', 'popRoute'},
      exempt: (path, method) =>
          path == _history || path == _routes && method == 'popPage',
      why:
          "is go_router's own, a new browser entry for a page closed; use "
          'popPage (or leave)',
    );
