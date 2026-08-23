import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/desktop/desktop_ports.dart';
import 'package:waxdeck/src/desktop/mini_window.dart';
import 'package:waxdeck/src/shell/commands.dart';

/// A window layer that answers whatever a compositor was going to, and
/// records what it was asked for.
class _FakeWindow implements MiniWindowPort {
  _FakeWindow(this.capabilities);

  MiniWindowCapabilities capabilities;
  final List<String> calls = <String>[];
  MiniWindowCapabilities? entered;

  @override
  Future<MiniWindowCapabilities> probe() async {
    calls.add('probe');
    return capabilities;
  }

  @override
  Future<void> enter(MiniWindowCapabilities capabilities) async {
    calls.add('enter');
    entered = capabilities;
  }

  @override
  Future<void> leave() async => calls.add('leave');

  @override
  Future<void> show() async => calls.add('show');

  @override
  Future<void> startDragging() async => calls.add('drag');

  @override
  Future<void> quit() async => calls.add('quit');

  /// What the app asked to run when the window is closed, so a test can
  /// close the window by calling it.
  Future<void> Function()? onClose;

  @override
  Future<void> bindClose(Future<void> Function() handler) async {
    calls.add('bindClose');
    onClose = handler;
  }

  @override
  Future<void> unbindClose() async {
    calls.add('unbindClose');
    onClose = null;
  }
}

ProviderContainer _container(_FakeWindow window) {
  final container = ProviderContainer(
    overrides: [miniWindowPortProvider.overrideWithValue(window)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('the mini window', () {
    test('is not offered where the platform has no window', () async {
      final window = _FakeWindow(MiniWindowCapabilities.none);
      final container = _container(window);
      container.read(miniWindowProvider);
      await container.pump();

      expect(container.read(miniWindowProvider).available, isFalse);
      await container.read(miniWindowProvider.notifier).enter();
      expect(container.read(miniWindowProvider).showing, isFalse);
      expect(window.calls, <String>['probe']);
    });

    test(
      'enters and leaves, and the app follows before the compositor does',
      () async {
        final window = _FakeWindow(
          const MiniWindowCapabilities(
            available: true,
            frameless: true,
            alwaysOnTop: true,
          ),
        );
        final container = _container(window);
        container.read(miniWindowProvider);
        await container.pump();

        await container.read(miniWindowProvider.notifier).enter();
        expect(container.read(miniWindowProvider).showing, isTrue);
        expect(window.entered!.frameless, isTrue);
        expect(window.entered!.alwaysOnTop, isTrue);

        await container.read(miniWindowProvider.notifier).leave();
        expect(container.read(miniWindowProvider).showing, isFalse);
        expect(window.calls, <String>['probe', 'enter', 'leave']);
      },
    );

    test('asks a Wayland session for only what it will give', () async {
      // The port is what reads the session type; what this pins is that
      // whatever it answers is what the app asks for, rather than the
      // app asking for everything and being refused mid-flight.
      final window = _FakeWindow(const MiniWindowCapabilities(available: true));
      final container = _container(window);
      container.read(miniWindowProvider);
      await container.pump();

      await container.read(miniWindowProvider.notifier).enter();
      expect(container.read(miniWindowProvider).showing, isTrue);
      expect(window.entered!.frameless, isFalse);
      expect(window.entered!.alwaysOnTop, isFalse);
    });

    test('a container torn down while small puts the window back', () async {
      final window = _FakeWindow(const MiniWindowCapabilities(available: true));
      final container = ProviderContainer(
        overrides: [miniWindowPortProvider.overrideWithValue(window)],
      );
      container.read(miniWindowProvider);
      await container.pump();
      await container.read(miniWindowProvider.notifier).enter();

      container.dispose();
      expect(window.calls, contains('leave'));
    });
  });

  group('its command', () {
    test('is absent from the registry where there is no window', () async {
      final container = _container(_FakeWindow(MiniWindowCapabilities.none));
      container.read(commandRegistryProvider);
      await container.pump();

      // Absent rather than disabled: a chord that can never work here
      // must not be bound, offered in the palette, or taught by the
      // reference sheet.
      expect(
        container.read(commandRegistryProvider).map((c) => c.id),
        isNot(contains('mini-window')),
      );
    });

    test('the probe resolving does not freeze the registry', () async {
      // Riverpod runs disposal callbacks before a recompute, on the same
      // notifier: a latched "closed" flag would make every scoped
      // command after launch a no-op.
      final container = _container(
        _FakeWindow(const MiniWindowCapabilities(available: true)),
      );
      // `CommandShortcuts` holds this for the session; without a
      // listener the registry is disposed between reads.
      container.listen(commandRegistryProvider, (_, _) {});
      final registry = container.read(commandRegistryProvider.notifier);
      await container.pump();
      // The probe has answered, so the registry has recomputed.
      expect(
        container.read(commandRegistryProvider).map((c) => c.id),
        contains('mini-window'),
      );

      final token = Object();
      registry.register(token, <WaxCommand>[
        WaxCommand(
          id: 'scoped-thing',
          label: 'Scoped thing',
          section: WaxCommandSection.app,
          run: (_, _) {},
        ),
      ]);
      expect(
        container.read(commandRegistryProvider).map((c) => c.id),
        contains('scoped-thing'),
      );

      registry.unregister(token);
      expect(
        container.read(commandRegistryProvider).map((c) => c.id),
        isNot(contains('scoped-thing')),
      );
    });

    test('appears once the probe says there is one', () async {
      final container = _container(
        _FakeWindow(const MiniWindowCapabilities(available: true)),
      );
      container.read(commandRegistryProvider);
      await container.pump();

      final command = container
          .read(commandRegistryProvider)
          .firstWhere((c) => c.id == 'mini-window');
      expect(command.section, WaxCommandSection.view);
      // Both spellings of the chord, so a keyboard moved between
      // machines finds what it expects.
      expect(command.activators, hasLength(2));
    });
  });
}
