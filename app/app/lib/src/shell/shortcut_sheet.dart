import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import 'commands.dart';
import 'semantics_ids.dart';

/// Opens the keyboard reference.
Future<void> showShortcutSheet(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _ShortcutSheetDialog(),
);

class _ShortcutSheetDialog extends ConsumerWidget {
  const _ShortcutSheetDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(commandRegistryProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WaxSpace.s16),
        child: WaxShortcutSheet(
          groups: shortcutGroups(commands),
          semanticsId: SemanticsIds.shortcutSheet,
          closeSemanticsId: SemanticsIds.shortcutSheetClose,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// Built from what is actually bound. Only commands with a keystroke
/// appear; sections keep their declared order.
List<WaxShortcutGroup> shortcutGroups(List<WaxCommand> commands) {
  return <WaxShortcutGroup>[
    for (final section in WaxCommandSection.values)
      WaxShortcutGroup(
        title: section.title,
        rows: <WaxShortcutRow>[
          for (final command in commands)
            if (command.section == section && command.keys != null)
              WaxShortcutRow(
                label: command.label,
                keys: command.keys!,
                semanticsId: SemanticsIds.shortcutSheetRow(command.id),
              ),
        ],
      ),
  ];
}
