import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fails the frame in which a semantics node's identifier changes while
/// nothing else on it does, in every widget test that keeps semantics on.
///
/// Flutter resends a node only when an annotation other than its
/// identifier changed, so such a node keeps its old identifier on the
/// platform side, where e2e drives the app by it. A list row matched by
/// position hands its node to the next row this way; a row keyed by what
/// it shows moves with it instead (lazy lists find it with `indexByKey`).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(_IdentifierWatch.start);
  tearDown(_IdentifierWatch.stop);
  await testMain();
}

abstract final class _IdentifierWatch {
  static bool _watching = false;
  static bool _hooked = false;
  static final _seen = <int, _Snapshot>{};

  static void start() {
    // A plain test never starts the binding, and starting one here would
    // hand its HTTP to flutter_test's stub.
    if (BindingBase.debugBindingType() == null) return;
    final binding = TestWidgetsFlutterBinding.instance;
    _seen.clear();
    _watching = true;
    if (!_hooked) {
      _hooked = true;
      binding.addPersistentFrameCallback((_) => _check(binding));
    }
  }

  static void stop() {
    _watching = false;
    _seen.clear();
  }

  static void _check(TestWidgetsFlutterBinding binding) {
    if (!_watching) return;
    final now = <int, _Snapshot>{};
    void visit(SemanticsNode node) {
      now[node.id] = _Snapshot(node);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    for (final view in binding.renderViews) {
      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root != null) visit(root);
    }
    final stale = <String>[
      for (final MapEntry(key: id, value: after) in now.entries)
        if (_seen[id] case final before?
            when before.identifier != after.identifier &&
                !after.merged &&
                // Flutter compares custom actions' callbacks, which only
                // their ids show here, and a rebuild remakes them.
                !after.hasCustomActions &&
                before.sameApartFromIdentifier(after))
          'node $id kept "${before.identifier}" on the platform when it '
              'became "${after.identifier}" (label "${after.data.label}")',
    ];
    _seen
      ..clear()
      ..addAll(now);
    if (stale.isNotEmpty) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('A semantics identifier changed on its own.'),
        ErrorDescription(stale.join('\n')),
        ErrorHint(
          'Flutter resends a node only when something besides its identifier '
          'changed. Key the row by what it shows, so it moves with it.',
        ),
      ]);
    }
  }
}

/// What Flutter compares to decide a node needs resending, and the
/// geometry and children that mark it dirty besides.
final class _Snapshot {
  _Snapshot(SemanticsNode node)
    : data = node.getSemanticsData(),
      merged = node.isMergedIntoParent,
      sortKey = node.sortKey,
      indexInParent = node.indexInParent,
      mergesDescendants = node.mergeAllDescendantsIntoThisNode,
      actionsBlocked = node.areUserActionsBlocked,
      children = _childIds(node);

  final SemanticsData data;
  final bool merged;
  final SemanticsSortKey? sortKey;
  final int? indexInParent;
  final bool mergesDescendants;
  final bool actionsBlocked;
  final List<int> children;

  String get identifier => data.identifier;

  bool get hasCustomActions =>
      data.customSemanticsActionIds?.isNotEmpty ?? false;

  static List<int> _childIds(SemanticsNode node) {
    final ids = <int>[];
    node.visitChildren((child) {
      ids.add(child.id);
      return true;
    });
    return ids;
  }

  bool sameApartFromIdentifier(_Snapshot other) {
    final a = data;
    final b = other.data;
    return a.attributedLabel == b.attributedLabel &&
        a.attributedHint == b.attributedHint &&
        a.attributedValue == b.attributedValue &&
        a.attributedIncreasedValue == b.attributedIncreasedValue &&
        a.attributedDecreasedValue == b.attributedDecreasedValue &&
        a.tooltip == b.tooltip &&
        a.flagsCollection == b.flagsCollection &&
        a.textDirection == b.textDirection &&
        a.textSelection == b.textSelection &&
        a.scrollPosition == b.scrollPosition &&
        a.scrollExtentMax == b.scrollExtentMax &&
        a.scrollExtentMin == b.scrollExtentMin &&
        a.actions == b.actions &&
        a.platformViewId == b.platformViewId &&
        a.maxValueLength == b.maxValueLength &&
        a.currentValueLength == b.currentValueLength &&
        a.headingLevel == b.headingLevel &&
        a.linkUrl == b.linkUrl &&
        a.role == b.role &&
        a.validationResult == b.validationResult &&
        a.hitTestBehavior == b.hitTestBehavior &&
        a.traversalParentIdentifier == b.traversalParentIdentifier &&
        a.traversalChildIdentifier == b.traversalChildIdentifier &&
        a.minValue == b.minValue &&
        a.maxValue == b.maxValue &&
        listEquals(a.customSemanticsActionIds, b.customSemanticsActionIds) &&
        a.rect == b.rect &&
        a.transform == b.transform &&
        sortKey == other.sortKey &&
        indexInParent == other.indexInParent &&
        mergesDescendants == other.mergesDescendants &&
        actionsBlocked == other.actionsBlocked &&
        listEquals(children, other.children);
  }
}
