import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/player/play_state_controller.dart';
import 'package:waxdeck/src/providers.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import 'fakes.dart';

// The optimistic-star race: server events (a playing session's own
// checkpoints) invalidate the play-state family, and a rebuild racing
// an unsettled mutation used to refetch the pre-mutation server state
// and visually revert the tap, with the write's result then lost on
// the disposed controller. Intents now overlay fresh builds until the
// write settles.

const pid = 'tr-01JZX5N8QW3F4V9T2B7KDEXAMPLE';

void main() {
  test('a family invalidation mid-star keeps the optimistic value', () async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final provider = playStateControllerProvider(pid);
    // A live listener, like the widgets: invalidation rebuilds eagerly.
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);

    await container.read(provider.future);
    expect(container.read(provider).value!.starred, isFalse);

    // Hold the PUT open and star.
    final gate = Completer<void>();
    repo.mutationGate = gate.future;
    final mutation = container.read(provider.notifier).setStarred(true);
    expect(
      container.read(provider).value!.starred,
      isTrue,
      reason: 'the tap applies optimistically',
    );

    // A checkpoint-driven invalidation lands mid-flight; the rebuilt
    // controller fetches the pre-commit server state but must overlay
    // the pending intent instead of reverting.
    container.invalidate(provider);
    await container.read(provider.future);
    expect(
      container.read(provider).value!.starred,
      isTrue,
      reason: 'a rebuild during the write must not revert the star',
    );

    // The write settles; state stays starred and nothing leaks.
    repo.mutationGate = null;
    gate.complete();
    await mutation;
    await container.read(provider.future);
    expect(container.read(provider).value!.starred, isTrue);
    expect(
      repo.starredByPid[pid],
      isTrue,
      reason: 'the write reached the server',
    );

    // A later clean rebuild fetches the committed state with no
    // overlay left behind.
    container.invalidate(provider);
    await container.read(provider.future);
    expect(container.read(provider).value!.starred, isTrue);
  });

  test('a rejected write settles its intent even after a rebuild', () async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final provider = playStateControllerProvider(pid);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    await container.read(provider.future);

    final gate = Completer<void>();
    repo.mutationGate = gate.future;
    repo.playStateError = const WaxDeckApiException(
      statusCode: 404,
      code: 'not-found',
      message: 'gone',
    );
    final mutation = container.read(provider.notifier).setStarred(true);

    container.invalidate(provider);
    await container.read(provider.future);

    repo.mutationGate = null;
    gate.complete();
    // The rejection lands on a disposed controller: it must neither
    // throw into the void nor strand its intent.
    await mutation;

    container.invalidate(provider);
    final settled = await container.read(provider.future);
    expect(
      settled.starred,
      isFalse,
      reason: 'a fresh build after the rejection fetches the truth',
    );
  });

  test('a non-API exception never strands the optimistic intent', () async {
    final repo = FakeRepository(items: [testItem(pid)]);
    final container = ProviderContainer(
      overrides: [repositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final provider = playStateControllerProvider(pid);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    await container.read(provider.future);

    // The gate itself blows up with a plain error, simulating a
    // repository bug outside the typed API exception.
    repo.mutationGate = Future<void>.error(StateError('boom'));
    await expectLater(
      container.read(provider.notifier).setStarred(true),
      throwsStateError,
    );
    repo.mutationGate = null;

    // The intent settled in the finally: a rebuild fetches the truth
    // instead of overlaying the failed tap forever.
    container.invalidate(provider);
    final settled = await container.read(provider.future);
    expect(
      settled.starred,
      isFalse,
      reason: 'a leaked intent would overlay every rebuild until restart',
    );
  });
}
