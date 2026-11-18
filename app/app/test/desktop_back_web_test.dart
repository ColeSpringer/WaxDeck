@TestOn('browser')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/providers.dart';

/// The web half of `desktop_back_test.dart`, which holds the binding to the
/// provider's answer on the VM: `kIsWeb` is false there, so only a browser
/// can say the answer is no whatever the operating system underneath is.
void main() {
  test('a browser keeps its back keys and button for itself', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(desktopBackProvider), isFalse);
  });
}
