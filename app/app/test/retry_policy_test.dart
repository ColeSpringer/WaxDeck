import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/admin/admin_providers.dart';
import 'package:waxdeck/src/admin/users_screen.dart';
import 'package:waxdeck/src/organize/organize_screen.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'app_host.dart';
import 'fakes.dart';

/// Every administrator's list refused, as for an account whose role was
/// taken away mid-session, counting the asks.
class _ListsRefused extends FakeRepository {
  final asked = <String, int>{};

  static const _refused = WaxDeckApiException(
    code: 'forbidden',
    message: 'not an administrator',
    statusCode: 403,
  );

  Never _refuse(String list) {
    asked[list] = (asked[list] ?? 0) + 1;
    throw _refused;
  }

  @override
  Future<List<Backup>> listBackups() async => _refuse('backups');

  @override
  Future<UserPage> listSignupRequests({String? cursor, int? limit}) async =>
      _refuse('signups');

  @override
  Future<List<Invite>> listInvites() async => _refuse('invites');

  @override
  Future<UserPage> listUsers({String? cursor, int? limit}) async =>
      _refuse('users');

  @override
  Future<OrganizeProfiles> listOrganizeProfiles() async => _refuse('profiles');
}

/// The one retry policy the app's server-backed providers share.
void main() {
  testWidgets("the administrators' lists take a refusal as final", (
    tester,
  ) async {
    final repo = _ListsRefused();
    final container = appContainer(repo: repo);
    container
      ..listen(backupsProvider, (_, _) {})
      ..listen(signupRequestsProvider, (_, _) {})
      ..listen(invitesProvider, (_, _) {})
      ..listen(adminUsersProvider, (_, _) {})
      ..listen(organizeProfilesProvider, (_, _) {});
    await tester.pumpWidget(const SizedBox());
    // Well past the default ladder's first few retries.
    await tester.pump(const Duration(seconds: 5));

    expect(repo.asked, {
      'backups': 1,
      'signups': 1,
      'invites': 1,
      'users': 1,
      'profiles': 1,
    });
  });

  test('a refusal is final', () {
    for (final status in <int>[400, 401, 404, 409, 429]) {
      expect(
        retryUnlessRefused(
          0,
          WaxDeckApiException(code: 'no', message: 'no', statusCode: status),
        ),
        isNull,
        reason: 'http $status',
      );
    }
  });

  test('a 4xx the server did not word keeps the ladder', () {
    // A proxy's page or an older server's router: not the server saying
    // no, so not final either.
    const proxied = WaxDeckApiException(
      code: 'transport',
      message: '404 page not found',
      statusCode: 404,
    );
    expect(retryUnlessRefused(0, proxied), isNotNull);
  });

  test('anything else keeps the default ladder, cap included', () {
    // A supplied policy replaces Riverpod's default rather than wrapping
    // it, so the cap only holds because this asks for it: without it an
    // unreachable server had a provider re-asking forever.
    final outage = WaxDeckApiException(
      code: 'internal',
      message: 'down',
      statusCode: 503,
    );
    expect(retryUnlessRefused(0, outage), isNotNull);
    expect(retryUnlessRefused(0, Exception('socket')), isNotNull);
    expect(retryUnlessRefused(9, outage), isNotNull);
    expect(retryUnlessRefused(10, outage), isNull, reason: 'the cap');
    expect(
      retryUnlessRefused(3, StateError('bug')),
      isNull,
      reason: 'a defect does not become a retry loop',
    );
    // The same schedule the default runs, so the two are one behaviour.
    expect(
      retryUnlessRefused(2, outage),
      ProviderContainer.defaultRetry(2, outage),
    );
  });
}
