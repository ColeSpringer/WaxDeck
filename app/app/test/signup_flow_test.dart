import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';

void main() {
  testWidgets('open signup queues the request and says so', (tester) async {
    final repo = FakeRepository();
    repo.adminSettings = repo.adminSettings.copyWith(signupEnabled: true);
    await pumpApp(
      tester,
      const LoginScreen(),
      container: appContainer(repo: repo),
    );

    // Open signup gets the louder label.
    expect(find.text('Request an account'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.signupOpen));
    await tester.pumpAndSettle();
    expect(find.textContaining('works right away'), findsNothing);

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.signupUsername),
      'pippin',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.signupPassword),
      'second-breakfast',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.signupSubmit));
    await tester.pumpAndSettle();

    final call = repo.signupCalls.single;
    expect(call.username, 'pippin');
    expect(call.inviteToken, isNull);
    expect(find.byKey(const Key(SemanticsIds.signupResult)), findsOneWidget);
    expect(find.textContaining('approve'), findsOneWidget);
  });

  testWidgets('an invite signup lands back on login prefilled', (tester) async {
    final repo = FakeRepository();
    await pumpApp(
      tester,
      const LoginScreen(),
      container: appContainer(repo: repo),
    );

    // Without open signup the link still serves invite holders.
    expect(find.text('Have an invite?'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.signupOpen));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.signupUsername),
      'sam',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.signupPassword),
      'po-ta-toes',
    );
    await tester.enterText(
      find.bySemanticsIdentifier(SemanticsIds.signupInviteToken),
      'invite-token-0',
    );
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.signupSubmit));
    await tester.pumpAndSettle();

    expect(repo.signupCalls.single.inviteToken, 'invite-token-0');
    // Back on the login form with the fresh username filled in.
    expect(
      find.bySemanticsIdentifier(SemanticsIds.loginSubmit),
      findsOneWidget,
    );
    expect(find.widgetWithText(WaxTextField, 'sam'), findsOneWidget);
  });

  testWidgets('the request form is the app\'s own page, and back is sign-in', (
    tester,
  ) async {
    await pumpApp(tester, const LoginScreen());
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.signupOpen));
    await tester.pumpAndSettle();

    expect(find.byType(WaxScaffold), findsOneWidget);
    expect(find.bySemanticsIdentifier(SemanticsIds.signupUsername), findsOne);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsIdentifier(SemanticsIds.loginSubmit), findsOne);
  });

  for (final (name, size) in <(String, Size)>[
    ('sits centred under the bar where there is room', const Size(800, 1000)),
    ('scrolls where there is not', const Size(800, 400)),
  ]) {
    testWidgets('the request form $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(tester, const LoginScreen());
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.signupOpen));
      await tester.pumpAndSettle();

      final form = tester.getRect(find.byType(Form));
      final bar = tester.getRect(find.byType(AppBar)).bottom;
      if (size.height > form.height * 2) {
        // As the sign-in form it came from is: in the middle of the page.
        expect(form.top - bar, closeTo(size.height - form.bottom, 1));
        expect(form.top - bar, greaterThan(WaxSpace.s48));
      } else {
        final submit = find.bySemanticsIdentifier(SemanticsIds.signupSubmit);
        // Scrolling lays the page out again, and must not build the form
        // again with it.
        final form = tester.widget<Form>(find.byType(Form));
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        expect(tester.widget<Form>(find.byType(Form)), same(form));
        expect(tester.getRect(submit).bottom, lessThanOrEqualTo(size.height));
      }
    });
  }
}
