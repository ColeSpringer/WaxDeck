import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/automation_semantics.dart';

void main() {
  _SpyBinding();

  testWidgets(
    'a host view attached to the running app gets the whole tree',
    semanticsEnabled: false,
    (tester) async {
      final hold = holdSemanticsForAutomation();
      final dispatcher = tester.binding.platformDispatcher;
      // A screen reader is on.
      dispatcher.semanticsEnabledTestValue = true;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              Semantics(
                container: true,
                label: 'Home',
                child: const SizedBox(width: 100, height: 10),
              ),
              Semantics(
                container: true,
                label: 'Search',
                child: const SizedBox(width: 100, height: 10),
              ),
            ],
          ),
        ),
      );
      expect(_SpyBuilder.nodes, contains(0));

      // The activity is relaunched with the engine kept: the old view turns
      // semantics off as it detaches, the new view's bridge starts empty and
      // turns it on, and holds only what is sent from here on.
      dispatcher.semanticsEnabledTestValue = false;
      await tester.pump();
      _SpyBuilder.nodes.clear();
      _SpyBuilder.labels.clear();
      dispatcher.semanticsEnabledTestValue = true;
      await tester.pump();

      final sentRoot = _SpyBuilder.nodes.contains(0);
      final sentLabels = [..._SpyBuilder.labels];
      hold?.dispose();
      dispatcher.clearSemanticsEnabledTestValue();
      expect(
        sentRoot,
        isTrue,
        reason: 'the new bridge never gets the root node',
      );
      expect(sentLabels, containsAll(['Home', 'Search']));
    },
  );

  testWidgets(
    'the web build holds semantics from the first frame',
    semanticsEnabled: false,
    (tester) async {
      final hold = holdSemanticsForAutomation(web: true);
      final enabled = SemanticsBinding.instance.semanticsEnabled;
      hold?.dispose();
      expect(hold, isNotNull);
      expect(enabled, isTrue);
    },
  );
}

class _SpyBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _SpyBuilder();
}

/// Records the nodes each semantics update sends, then builds it for real.
class _SpyBuilder implements ui.SemanticsUpdateBuilder {
  static final nodes = <int>{};
  static final labels = <String>[];
  final _real = ui.SemanticsUpdateBuilder();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final Function member;
    switch (invocation.memberName) {
      case #updateNode:
        nodes.add(invocation.namedArguments[#id]! as int);
        labels.add(invocation.namedArguments[#label]! as String);
        member = _real.updateNode;
      case #updateCustomAction:
        member = _real.updateCustomAction;
      case #build:
        member = _real.build;
      default:
        return super.noSuchMethod(invocation);
    }
    return Function.apply(
      member,
      invocation.positionalArguments,
      invocation.namedArguments,
    );
  }
}
