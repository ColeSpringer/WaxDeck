import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/auth/auth_controller.dart';
import 'package:waxdeck/src/auth/credential_store.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck/src/review/review_controller.dart';
import 'package:waxdeck/src/tools/tool_tasks_provider.dart';
import 'package:waxdeck/src/uploads/uploads_controller.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

/// What one account read is read again for the next one on the same
/// server: the repository moves only with the server, so a list kept
/// for the session would otherwise show the last account's rows.

const _ann = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCANN',
  username: 'ann',
  roles: ['user'],
  uploadEnabled: true,
);
const _ben = WaxDeckUser(
  id: 'us-01JZX5N8QW3F4V9T2B7KDACCBEN',
  username: 'ben',
  roles: ['user'],
  uploadEnabled: true,
);

/// What the server holds for [who]: Ann has two entries waiting, an
/// upload and a task; Ben one entry, and an upload and a task of his own.
void _holdFor(FakeRepository repo, WaxDeckUser who) {
  final ann = who == _ann;
  final at = DateTime.utc(2026, 10, 1);
  repo
    ..reviewEntries = [
      if (ann) ...[testReviewEntry('rv-ann1'), testReviewEntry('rv-ann2')],
      if (!ann) testReviewEntry('rv-ben1'),
    ]
    ..uploadsById.clear()
    ..uploadsById['up-${who.username}'] = UploadSession(
      id: 'up-${who.username}',
      fileName: '${who.username}.flac',
      sizeBytes: 8,
      receivedBytes: 8,
      mediaType: MediaType.music,
      state: 'staged',
      createdAt: at,
    )
    ..toolTasksById.clear()
    ..toolTasksById['tt-${who.username}'] = ToolTask(
      id: 'tt-${who.username}',
      type: 'acquire',
      state: 'done',
      createdAt: at,
    );
}

void main() {
  for (final (name, provider, read, annSees, benSees)
      in <
        (
          String,
          ProviderListenable<Object?>,
          Future<Object?> Function(ProviderContainer),
          Object?,
          Object?,
        )
      >[
        (
          'the review counts',
          reviewStatsProvider,
          (c) async => (await c.read(reviewStatsProvider.future)).pending,
          2,
          1,
        ),
        (
          'home\'s review count',
          pendingReviewCountProvider,
          (c) => c.read(pendingReviewCountProvider.future),
          2,
          1,
        ),
        (
          'the review queue',
          reviewQueueProvider,
          (c) async => [
            for (final e in (await c.read(reviewQueueProvider.future)).entries)
              e.id,
          ],
          ['rv-ann1', 'rv-ann2'],
          ['rv-ben1'],
        ),
        (
          'the uploads',
          uploadsProvider,
          (c) async => [
            for (final u in (await c.read(uploadsProvider.future)).uploads)
              u.id,
          ],
          ['up-ann'],
          ['up-ben'],
        ),
        (
          'the tool tasks',
          toolTasksProvider,
          (c) async => [
            for (final t in (await c.read(toolTasksProvider.future)).tasks)
              t.id,
          ],
          ['tt-ann'],
          ['tt-ben'],
        ),
      ]) {
    test('reads $name again for the next account on the server', () async {
      final repo = FakeRepository(
        sessionState: const SessionState(authenticated: true, user: _ann),
      );
      _holdFor(repo, _ann);
      final container = ProviderContainer(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          credentialStoreProvider.overrideWithValue(InMemoryCredentialStore()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      // Kept alive, as the screen showing it would.
      final held = container.listen(provider, (_, _) {});
      addTearDown(held.close);
      expect(await read(container), annSees);

      // Ben signs in on the same server.
      _holdFor(repo, _ben);
      repo.sessionState = const SessionState(authenticated: true, user: _ben);
      await container.read(authControllerProvider.notifier).refreshSession();

      expect(await read(container), benSees);
    });
  }
}
