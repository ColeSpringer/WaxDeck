import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/connect_server_screen.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/auth/setup_screen.dart';
import 'package:waxdeck/src/auth/signup_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'fakes.dart';
import 'routed_host.dart';
import 'wax_finders.dart';

Widget _host(Widget screen) => ProviderScope(
  overrides: [repositoryProvider.overrideWithValue(FakeRepository())],
  child: routedHost(screen),
);

Finder _id(String id) => find.bySemanticsIdentifier(id);

/// [message] drawn inside the field that owns [id].
Finder _under(String id, String message) => find.descendant(
  of: waxControl<WaxTextField>(id),
  matching: find.text(message),
);

void main() {
  testWidgets('the login form is made of Wax controls', (tester) async {
    await tester.pumpWidget(_host(const LoginScreen()));
    await tester.pump();
    for (final id in [SemanticsIds.loginUsername, SemanticsIds.loginPassword]) {
      expect(
        tester.widget<WaxTextField>(waxControl<WaxTextField>(id)).validator,
        isNotNull,
      );
    }
    expect(waxControl<WaxButton>(SemanticsIds.loginSubmit), findsOneWidget);
    expect(waxControl<WaxButton>(SemanticsIds.signupOpen), findsOneWidget);
  });

  testWidgets('the login button shows busy while signing in', (tester) async {
    final repo = FakeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: routedHost(const LoginScreen()),
      ),
    );
    await tester.enterText(_id(SemanticsIds.loginUsername), 'admin');
    await tester.enterText(_id(SemanticsIds.loginPassword), 'nope');
    await tester.tap(_id(SemanticsIds.loginSubmit));
    await tester.pump();
    expect(
      tester
          .widget<WaxButton>(waxControl<WaxButton>(SemanticsIds.loginSubmit))
          .busy,
      true,
    );
  });

  testWidgets('the setup form flags each bad field on the field itself', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const SetupScreen()));
    await tester.pump();
    expect(waxControl<WaxButton>(SemanticsIds.setupSubmit), findsOneWidget);
    expect(
      waxControl<WaxTextField>(SemanticsIds.setupUsername),
      findsOneWidget,
    );

    await tester.tap(_id(SemanticsIds.setupSubmit));
    await tester.pump();
    expect(
      _under(SemanticsIds.setupUsername, 'Enter a username'),
      findsOneWidget,
    );
    expect(
      _under(SemanticsIds.setupPassword, 'Use at least 8 characters'),
      findsOneWidget,
    );
    expect(find.text('Passwords do not match'), findsNothing);

    await tester.enterText(_id(SemanticsIds.setupUsername), 'admin');
    await tester.enterText(_id(SemanticsIds.setupPassword), 'long-enough');
    await tester.enterText(_id(SemanticsIds.setupConfirm), 'different');
    await tester.tap(_id(SemanticsIds.setupSubmit));
    await tester.pump();
    expect(find.text('Enter a username'), findsNothing);
    expect(find.text('Use at least 8 characters'), findsNothing);
    expect(
      _under(SemanticsIds.setupConfirm, 'Passwords do not match'),
      findsOneWidget,
    );
  });

  testWidgets('the signup form flags each bad field on the field itself', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const SignupScreen()));
    await tester.pump();
    expect(waxControl<WaxButton>(SemanticsIds.signupSubmit), findsOneWidget);
    expect(
      waxControl<WaxTextField>(SemanticsIds.signupInviteToken),
      findsOneWidget,
    );

    await tester.tap(_id(SemanticsIds.signupSubmit));
    await tester.pump();
    expect(
      _under(SemanticsIds.signupUsername, 'Choose a username'),
      findsOneWidget,
    );
    expect(
      _under(SemanticsIds.signupPassword, 'Choose a password'),
      findsOneWidget,
    );

    await tester.enterText(_id(SemanticsIds.signupUsername), 'pippin');
    await tester.tap(_id(SemanticsIds.signupSubmit));
    await tester.pump();
    expect(find.text('Choose a username'), findsNothing);
    expect(
      _under(SemanticsIds.signupPassword, 'Choose a password'),
      findsOneWidget,
    );
  });

  testWidgets('the connect screen is made of Wax controls', (tester) async {
    await tester.pumpWidget(_host(const ConnectServerScreen()));
    await tester.pump();
    expect(
      waxControl<WaxTextField>(SemanticsIds.connectServerAddress),
      findsOneWidget,
    );
    expect(
      waxControl<WaxButton>(SemanticsIds.connectServerSubmit),
      findsOneWidget,
    );
  });
}
