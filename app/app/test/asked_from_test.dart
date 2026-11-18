import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/shell/asked_from.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'localized_host.dart';

const _page = Key('page');
const _surface = Key('surface');

/// Who is signed in, as the test says.
class _Who extends Notifier<String?> {
  @override
  String? build() => 'ada';

  void signIn(String? account) => state = account;
}

final _who = NotifierProvider<_Who, String?>(_Who.new);

/// The app's host around a page, over a container whose account the test
/// moves, with every message raised to the shell kept in [raised].
Future<ProviderContainer> _host(
  WidgetTester tester,
  List<String> raised, {
  Widget? host,
}) async {
  final container = appContainer(
    extra: [signedInAccountProvider.overrideWith((ref) => ref.watch(_who))],
  );
  container.listen(shellMessagesProvider, (_, message) {
    if (message != null) raised.add(message.resolve(AppLocalizationsEn()));
  });
  await mountHost(
    tester,
    host ?? localizedHost(const SizedBox(key: _page)),
    container: container,
  );
  await tester.pumpAndSettle();
  return container;
}

/// Opens a dialog over the page, and answers the context inside it.
Future<BuildContext> _openSurface(WidgetTester tester) async {
  unawaited(
    showDialog<void>(
      context: tester.element(find.byKey(_page)),
      builder: (_) => const SizedBox(key: _surface),
    ),
  );
  await tester.pumpAndSettle();
  return tester.element(find.byKey(_surface));
}

void main() {
  testWidgets('a refusal is said on the surface while it is still there', (
    tester,
  ) async {
    final raised = <String>[];
    await _host(tester, raised);
    final from = AskedFrom.of(await _openSurface(tester));
    final inline = <String>[];

    from.refused('taken', inline: inline.add, channel: ShellChannel.radio);

    expect(from.stillThere, isTrue);
    expect(inline, ['taken']);
    expect(raised, isEmpty);
  });

  testWidgets('something opened over the surface leaves it there', (
    tester,
  ) async {
    final raised = <String>[];
    await _host(tester, raised);
    final surface = await _openSurface(tester);
    final from = AskedFrom.of(surface);
    unawaited(
      showDialog<void>(context: surface, builder: (_) => const SizedBox()),
    );
    await tester.pumpAndSettle();
    final inline = <String>[];

    from.refused('taken', inline: inline.add);

    expect(inline, ['taken']);
    expect(raised, isEmpty);
  });

  testWidgets('a surface dismissed is said in the shell, on its way out and '
      'once gone', (tester) async {
    final raised = <String>[];
    await _host(tester, raised);
    final surface = await _openSurface(tester);
    final from = AskedFrom.of(surface);
    final inline = <String>[];

    Navigator.of(surface).pop();
    await tester.pump();
    expect(find.byKey(_surface), findsOneWidget, reason: 'on its way out');
    from.refused('taken', inline: inline.add);
    await tester.pumpAndSettle();
    from.refused('still taken', inline: inline.add);

    expect(from.stillThere, isFalse);
    expect(inline, isEmpty);
    expect(raised, ['taken', 'still taken']);
  });

  testWidgets('a surface in no route is there while it is mounted', (
    tester,
  ) async {
    final raised = <String>[];
    final container = await _host(
      tester,
      raised,
      host: const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(key: _surface),
      ),
    );
    final from = AskedFrom.of(tester.element(find.byKey(_surface)));
    final inline = <String>[];

    expect(from.route, isNull);
    from.refused('taken', inline: inline.add);
    expect(inline, ['taken']);

    await leaveScreen(tester, container);
    from.refused('still taken', inline: inline.add);
    expect(inline, ['taken']);
    expect(raised, ['still taken']);
  });

  testWidgets('with no place of its own on the surface, the shell says it', (
    tester,
  ) async {
    final raised = <String>[];
    await _host(tester, raised);
    final from = AskedFrom.of(await _openSurface(tester));

    from.refused('taken');

    expect(raised, ['taken']);
  });

  testWidgets('a dialog is shown over what is on screen once the surface '
      'has gone', (tester) async {
    final raised = <String>[];
    await _host(tester, raised);
    final surface = await _openSurface(tester);
    final from = AskedFrom.of(surface);
    Navigator.of(surface).pop();
    await tester.pumpAndSettle();

    unawaited(from.showDialogOnScreen<void>(builder: (_) => const Text('s3')));
    await tester.pumpAndSettle();

    expect(find.text('s3'), findsOneWidget);
  });

  testWidgets('no dialog once the session that asked has ended', (
    tester,
  ) async {
    final raised = <String>[];
    final container = await _host(tester, raised);
    final from = AskedFrom.of(await _openSurface(tester));
    container.read(_who.notifier).signIn('grace');

    final shown = from.showDialogOnScreen<bool>(
      builder: (_) => const Text('s3'),
    );
    await tester.pumpAndSettle();

    expect(await shown, isNull);
    expect(find.text('s3'), findsNothing);
  });
}
