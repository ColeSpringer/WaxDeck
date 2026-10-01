import 'package:flutter_test/flutter_test.dart';

/// Runs [change], expecting every identifier in [ids] drawn before it to
/// sit on the same semantics node after it.
///
/// Flutter resends a node only when an annotation other than its
/// identifier changed, so a row whose node passed to another row by
/// position keeps the old identifier where e2e reads it. Rows keyed by what
/// they show move with it, node and all.
Future<void> expectRowsKeepTheirNodes(
  WidgetTester tester,
  List<String> ids,
  Future<void> Function() change,
) async {
  Map<String, int> nodes() => {
    for (final id in ids)
      if (find.bySemanticsIdentifier(id).evaluate().isNotEmpty)
        id: tester.getSemantics(find.bySemanticsIdentifier(id)).id,
  };
  final before = nodes();
  expect(before.keys, ids, reason: 'every row followed is drawn first');
  await change();
  final after = nodes();
  for (final MapEntry(key: id, value: node) in before.entries) {
    expect(after[id], node, reason: '$id should stay on node $node');
  }
}
