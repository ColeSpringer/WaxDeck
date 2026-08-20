import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/shell/async_sliver_face.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'localized_host.dart';

/// A provider whose every build hangs until the test resolves it, so
/// the state a refresh actually produces - loading, still carrying the
/// value it had - can be held still and looked at. That state is
/// neither `AsyncData` nor `AsyncError`, which is why a switch on the
/// runtime type falls through to its skeleton arm and blanks the
/// screen.
class _Rows extends AsyncNotifier<List<String>> {
  static Completer<List<String>> next = Completer<List<String>>();

  @override
  Future<List<String>> build() => next.future;
}

final _rowsProvider = AsyncNotifierProvider<_Rows, List<String>>(_Rows.new);

/// Resolves the pending build and lets the frame land.
Future<void> _resolve(WidgetTester tester, List<String> rows) async {
  _Rows.next.complete(rows);
  await tester.pumpAndSettle();
}

/// Fails the pending build.
Future<void> _fail(WidgetTester tester) async {
  _Rows.next.completeError(Exception('nope'), StackTrace.empty);
  await tester.pumpAndSettle();
}

/// Invalidates without resolving, leaving the provider in the refresh
/// state under test.
Future<void> _refresh(WidgetTester tester) async {
  _Rows.next = Completer<List<String>>();
  ProviderScope.containerOf(
    tester.element(find.byType(CustomScrollView)),
  ).invalidate(_rowsProvider);
  await tester.pump();
}

class _Host extends ConsumerWidget {
  const _Host({this.withEmptyFace = true});

  final bool withEmptyFace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_rowsProvider);
    return CustomScrollView(
      slivers: <Widget>[
        AsyncSliverFace<List<String>>(
          state: state,
          errorTitle: 'Could not load',
          onRetry: () => ref.invalidate(_rowsProvider),
          isEmpty: withEmptyFace ? (value) => value.isEmpty : null,
          empty: withEmptyFace
              ? (context) => const SliverToBoxAdapter(
                  child: EmptyState(title: 'Nothing here', message: 'Add one'),
                )
              : null,
          builder: (context, value) => SliverList.builder(
            itemCount: value.length,
            itemBuilder: (context, i) => Text(value[i]),
          ),
        ),
      ],
    );
  }
}

Future<void> _pump(WidgetTester tester, {bool withEmptyFace = true}) async {
  _Rows.next = Completer<List<String>>();
  await tester.pumpWidget(
    ProviderScope(child: localizedHost(_Host(withEmptyFace: withEmptyFace))),
  );
  await tester.pump();
}

void main() {
  testWidgets('a first load with nothing held draws the skeleton', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(SkeletonShapes), findsOneWidget);
    await _resolve(tester, const <String>['Alpha']);
  });

  testWidgets('a refresh redraws the rows it already has', (tester) async {
    await _pump(tester);
    await _resolve(tester, const <String>['Alpha', 'Bravo']);

    await _refresh(tester);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);
    expect(
      find.byType(SkeletonShapes),
      findsNothing,
      reason: 'a reload must not blank content the screen already holds',
    );
    await _resolve(tester, const <String>['Alpha', 'Bravo']);
  });

  testWidgets('an empty result keeps its own face through a refresh', (
    tester,
  ) async {
    await _pump(tester);
    await _resolve(tester, const <String>[]);
    expect(find.text('Nothing here'), findsOneWidget);

    await _refresh(tester);

    expect(
      find.text('Nothing here'),
      findsOneWidget,
      reason: 'the empty state is a result, not the absence of one',
    );
    expect(find.byType(SkeletonShapes), findsNothing);
    await _resolve(tester, const <String>[]);
  });

  testWidgets('a retry in flight keeps the failure it is retrying', (
    tester,
  ) async {
    await _pump(tester);
    await _fail(tester);
    expect(find.byType(ErrorState), findsOneWidget);

    await _refresh(tester);

    expect(find.byType(ErrorState), findsOneWidget);
    expect(
      find.byType(SkeletonShapes),
      findsNothing,
      reason: 'Riverpod retries on its own; the card must not flash away',
    );
    await _resolve(tester, const <String>['Alpha']);
  });

  testWidgets('a failure wins over the rows it could not refresh', (
    tester,
  ) async {
    await _pump(tester);
    await _resolve(tester, const <String>['Alpha']);

    await _refresh(tester);
    await _fail(tester);

    expect(find.byType(ErrorState), findsOneWidget);
    expect(
      find.text('Alpha'),
      findsNothing,
      reason: 'rows that failed to reload may be wrong; say so',
    );
  });

  testWidgets('without an empty face an empty value goes to the builder', (
    tester,
  ) async {
    await _pump(tester, withEmptyFace: false);
    await _resolve(tester, const <String>[]);
    expect(find.text('Nothing here'), findsNothing);
    expect(find.byType(SkeletonShapes), findsNothing);
  });
}
