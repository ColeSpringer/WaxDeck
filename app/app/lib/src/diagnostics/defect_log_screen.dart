import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'defect_log.dart';

/// What the app caught that nobody was there to see.
///
/// The reason this screen exists rather than a snackbar: a defect here
/// is a programming error, not something a listener can act on, and the
/// only useful thing to do with one is put it in a bug report. So it is
/// under About, beside the version numbers that report gets asked for,
/// with one control that copies the lot.
class DefectLogScreen extends ConsumerStatefulWidget {
  const DefectLogScreen({super.key});

  @override
  ConsumerState<DefectLogScreen> createState() => _DefectLogScreenState();
}

class _DefectLogScreenState extends ConsumerState<DefectLogScreen> {
  Future<void> _copy() async {
    final report = ref.read(defectLogProvider.notifier).report();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Defect log copied')));
  }

  @override
  Widget build(BuildContext context) {
    final defects = ref.watch(defectLogProvider);
    final colors = WaxColors.of(context);
    final sizeClass = WaxSizeClass.of(context);
    return WaxScaffold(
      title: 'Defect log',
      largeTitle: false,
      semanticsId: SemanticsIds.defectsScreen,
      onBack: () => context.leave(fallback: WaxRoute.settingsAbout),
      slivers: <Widget>[
        if (defects.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: 'Nothing has gone wrong',
              message:
                  'Errors the app catches on its own turn up here, so a bug '
                  'report can carry them. An empty list is the good outcome.',
              glyph: WaxIcons.info,
            ),
          )
        else
          SliverPadding(
            padding: sizeClass.gutter,
            // Built lazily: fifty entries of clipped monospace are
            // hundreds of kilobytes of laid-out text, and this is the
            // screen somebody reaches exactly when frames are already
            // failing.
            sliver: SliverList.builder(
              itemCount: defects.length + 2,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return ReadingColumn(
                    child: Padding(
                      padding: const EdgeInsets.only(top: WaxSpace.s16),
                      child: Row(
                        children: <Widget>[
                          WaxButton(
                            label: 'Copy',
                            spokenLabel: 'Copy the defect log',
                            kind: WaxButtonKind.text,
                            semanticsId: SemanticsIds.defectsCopy,
                            onPressed: _copy,
                          ),
                          const SizedBox(width: WaxSpace.s16),
                          // No confirmation and no snackbar: the ring
                          // only holds diagnostics, and the empty state
                          // this flips to is the feedback.
                          WaxButton(
                            label: 'Clear',
                            spokenLabel: 'Clear the defect log',
                            kind: WaxButtonKind.text,
                            semanticsId: SemanticsIds.defectsClear,
                            onPressed: () =>
                                ref.read(defectLogProvider.notifier).clear(),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (i == defects.length + 1) {
                  return const SizedBox(height: WaxSpace.s32);
                }
                final d = defects[i - 1];
                return ReadingColumn(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(height: WaxSpace.s16),
                      Text(
                        d.count > 1
                            ? '${d.at.toIso8601String()} [${d.source}] x${d.count}'
                            : '${d.at.toIso8601String()} [${d.source}]',
                        style: WaxType.overline.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: WaxSpace.s4),
                      MonoDetailRow(label: 'error', value: d.summary),
                      if (d.details.isNotEmpty)
                        MonoDetailRow(label: 'stack', value: d.details),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
