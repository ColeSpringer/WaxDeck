import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waxdeck/src/settings/client_prefs.dart';
import 'package:waxdeck/src/settings/integrations_sections.dart';
import 'package:waxdeck/src/shell/semantics_ids.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'localized_host.dart';

void main() {
  testWidgets('presence can go without album covers', (tester) async {
    // Covers are this device asking the archive; somebody may not want to.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(discordPresenceEnabledProvider.notifier).set(true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedHost(
          const Scaffold(
            body: SingleChildScrollView(child: DiscordPresenceSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(discordCoversEnabledProvider), isTrue);

    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.setting('discord-covers')),
    );
    await tester.pumpAndSettle();

    expect(container.read(discordCoversEnabledProvider), isFalse);
    expect(find.textContaining('asks the Cover Art Archive'), findsOneWidget);
  });
}
