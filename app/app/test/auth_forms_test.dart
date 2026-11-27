import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/connect_server_screen.dart';
import 'package:waxdeck/src/auth/login_screen.dart';
import 'package:waxdeck/src/auth/setup_screen.dart';
import 'package:waxdeck/src/auth/signup_screen.dart';
import 'package:waxdeck/src/l10n/gen/app_localizations_en.dart';
import 'package:waxdeck/src/l10n/l10n.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck/src/shell/shell_messages.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'app_host.dart';
import 'fakes.dart';
import 'wax_finders.dart';

Finder _id(String id) => find.bySemanticsIdentifier(id);

/// [message] drawn inside the field that owns [id].
Finder _under(String id, String message) => find.descendant(
  of: waxControl<WaxTextField>(id),
  matching: find.text(message),
);

void main() {
  group('a refusal answered', () {
    const typed = WaxDeckApiException(
      code: 'invalid_argument',
      message: 'username must be 3 to 32 characters',
    );

    /// [screen] over [repo], its form filled by [fill] and sent by
    /// [submit], held at [gate], then let go while the page is up or once
    /// it has gone where [left]: the sentence under the form, and the one
    /// the shell was told.
    Future<(String?, String?)> answered(
      WidgetTester tester,
      Widget screen,
      FakeRepository repo,
      Completer<void> gate, {
      required bool left,
      required Future<void> Function() fill,
      required String submit,
      required String error,
    }) async {
      final container = appContainer(repo: repo);
      await mountApp(tester, screen, container: container);
      await tester.pump();
      await fill();
      await tester.tap(_id(submit));
      await tester.pump();
      if (left) await leaveScreen(tester, container);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final under = find.byKey(Key(error));
      return (
        under.evaluate().isEmpty ? null : tester.widget<Text>(under).data,
        shellMessageText(container.read(shellMessagesProvider)),
      );
    }

    for (final left in <bool>[false, true]) {
      final where = left
          ? 'once its page has gone is said in the shell'
          : 'while its page is up is said under the form';

      testWidgets('to a sign-in $where', (tester) async {
        final gate = Completer<void>();
        final repo = FakeRepository()
          ..loginGate = gate
          ..loginError = const WaxDeckApiException(
            code: 'unauthenticated',
            message: 'invalid credentials',
            statusCode: 401,
          );
        final said = AppLocalizationsEn().authSignInRejected;
        final (under, shell) = await answered(
          tester,
          const LoginScreen(),
          repo,
          gate,
          left: left,
          fill: () async {
            await tester.enterText(_id(SemanticsIds.loginUsername), 'admin');
            await tester.enterText(_id(SemanticsIds.loginPassword), 'nope');
          },
          submit: SemanticsIds.loginSubmit,
          error: SemanticsIds.loginError,
        );
        expect(under, left ? isNull : said);
        expect(shell, left ? said : isNull);
      });

      testWidgets('to a first run $where', (tester) async {
        final gate = Completer<void>();
        final repo = FakeRepository()
          ..bootstrapGate = gate
          ..bootstrapError = typed;
        final said = explainRefusal(AppLocalizationsEn(), typed);
        final (under, shell) = await answered(
          tester,
          const SetupScreen(),
          repo,
          gate,
          left: left,
          fill: () async {
            await tester.enterText(_id(SemanticsIds.setupUsername), 'admin');
            await tester.enterText(
              _id(SemanticsIds.setupPassword),
              'long-enough',
            );
            await tester.enterText(
              _id(SemanticsIds.setupConfirm),
              'long-enough',
            );
          },
          submit: SemanticsIds.setupSubmit,
          error: SemanticsIds.setupError,
        );
        expect(under, left ? isNull : said);
        expect(shell, left ? said : isNull);
      });

      testWidgets('to a sign-up $where', (tester) async {
        final gate = Completer<void>();
        final repo = FakeRepository()
          ..signupGate = gate
          ..signupError = typed;
        final said = explainRefusal(AppLocalizationsEn(), typed);
        final (under, shell) = await answered(
          tester,
          const SignupScreen(),
          repo,
          gate,
          left: left,
          fill: () async {
            await tester.enterText(_id(SemanticsIds.signupUsername), 'sam');
            await tester.enterText(
              _id(SemanticsIds.signupPassword),
              'po-ta-toes',
            );
          },
          submit: SemanticsIds.signupSubmit,
          error: SemanticsIds.signupError,
        );
        expect(under, left ? isNull : said);
        expect(shell, left ? said : isNull);
      });
    }
  });

  // What each credential form tells a password manager as its screen moves
  // on: saved only once the credentials were taken. Ending the context is
  // also what takes the web engine's hidden form, and the values typed
  // into it, back out of the page.
  group('autofill', () {
    List<bool> ended(WidgetTester tester) => [
      for (final call in tester.testTextInput.log)
        if (call.method == 'TextInput.finishAutofillContext')
          call.arguments as bool,
    ];

    testWidgets('a sign-in that lands offers its credentials for saving', (
      tester,
    ) async {
      await mountApp(tester, const LoginScreen());
      await tester.pump();
      await tester.enterText(_id(SemanticsIds.loginUsername), 'admin');
      await tester.enterText(_id(SemanticsIds.loginPassword), 'hunter-two');
      await tester.tap(_id(SemanticsIds.loginSubmit));
      // Signed in, the shell's own animations never settle.
      await tester.pump();
      await tester.pump();
      expect(ended(tester).first, isTrue);
    });

    testWidgets('a refused sign-in keeps its context open', (tester) async {
      final repo = FakeRepository()
        ..loginError = const WaxDeckApiException(
          code: 'unauthenticated',
          message: 'invalid credentials',
          statusCode: 401,
        );
      await mountApp(
        tester,
        const LoginScreen(),
        container: appContainer(repo: repo),
      );
      await tester.pump();
      await tester.enterText(_id(SemanticsIds.loginUsername), 'admin');
      await tester.enterText(_id(SemanticsIds.loginPassword), 'nope');
      await tester.tap(_id(SemanticsIds.loginSubmit));
      await tester.pumpAndSettle();
      expect(ended(tester), isEmpty);
    });

    testWidgets('a first run that lands offers the administrator for saving', (
      tester,
    ) async {
      await mountApp(tester, const SetupScreen());
      await tester.pump();
      await tester.enterText(_id(SemanticsIds.setupUsername), 'admin');
      await tester.enterText(_id(SemanticsIds.setupPassword), 'long-enough');
      await tester.enterText(_id(SemanticsIds.setupConfirm), 'long-enough');
      await tester.tap(_id(SemanticsIds.setupSubmit));
      await tester.pump();
      await tester.pump();
      expect(ended(tester).first, isTrue);
    });

    for (final invite in <String?>['inv-token', null]) {
      testWidgets(
        'a sign-up the server takes ${invite == null ? 'as pending' : 'as active'} '
        'offers the account for saving',
        (tester) async {
          await mountApp(tester, const SignupScreen(), pushed: true);
          await tester.pumpAndSettle();
          await tester.enterText(_id(SemanticsIds.signupUsername), 'sam');
          await tester.enterText(
            _id(SemanticsIds.signupPassword),
            'po-ta-toes',
          );
          if (invite != null) {
            await tester.enterText(_id(SemanticsIds.signupInviteToken), invite);
          }
          await tester.tap(_id(SemanticsIds.signupSubmit));
          await tester.pumpAndSettle();
          expect(ended(tester), <bool>[true]);
        },
      );
    }

    testWidgets('backing out of sign-up drops what was typed, unsaved', (
      tester,
    ) async {
      await mountApp(tester, const SignupScreen(), pushed: true);
      await tester.pumpAndSettle();
      await tester.enterText(_id(SemanticsIds.signupUsername), 'sam');
      await tester.enterText(_id(SemanticsIds.signupPassword), 'po-ta-toes');
      await tester.tap(_id(SemanticsIds.navBack));
      await tester.pumpAndSettle();
      expect(find.byType(SignupScreen), findsNothing);
      expect(ended(tester), <bool>[false]);
    });
  });

  testWidgets('the login form is made of Wax controls', (tester) async {
    await mountApp(tester, const LoginScreen());
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
    await mountApp(
      tester,
      const LoginScreen(),
      container: appContainer(repo: repo),
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
    await mountApp(tester, const SetupScreen());
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
    await mountApp(tester, const SignupScreen());
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
    await mountApp(tester, const ConnectServerScreen());
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
