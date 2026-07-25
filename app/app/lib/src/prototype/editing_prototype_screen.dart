import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../shell/semantics_ids.dart';

/// A data-dense editing prototype shaped like the metadata review
/// queue: a static-data table exercising exactly the interactions
/// canvas rendering is weakest at, so the go/no-go verdict rests on
/// evidence instead of folklore. Text selection and clipboard copy,
/// right-click context menus, and a column of live text fields all in
/// one screen; reachable unauthenticated at /prototype/editing because
/// it renders synthesized rows and talks to nothing.
class EditingPrototypeScreen extends StatefulWidget {
  const EditingPrototypeScreen({super.key});

  @override
  State<EditingPrototypeScreen> createState() => _EditingPrototypeScreenState();
}

class _Row {
  _Row(this.currentTitle, this.proposedTitle, this.artist, this.confidence);

  final String currentTitle;
  final String proposedTitle;
  final String artist;
  final int confidence;
}

class _EditingPrototypeScreenState extends State<EditingPrototypeScreen> {
  late final List<_Row> rows;
  late final List<TextEditingController> proposed;

  @override
  void initState() {
    super.initState();
    rows = List.generate(
      60,
      (i) => _Row(
        'track ${i.toString().padLeft(2, '0')} - untagged',
        'Proposed Title ${i.toString().padLeft(2, '0')}',
        'Proposed Artist ${(i ~/ 12) + 1}',
        99 - i,
      ),
    );
    proposed = [
      for (final r in rows) TextEditingController(text: r.proposedTitle),
    ];
  }

  @override
  void dispose() {
    for (final c in proposed) {
      c.dispose();
    }
    super.dispose();
  }

  /// The per-row action menu, opened from the kebab or a secondary
  /// click on the row. Secondary clicks over the selection area may be
  /// claimed by the selection toolbar first, which is itself part of
  /// what the prototype measures; the kebab is the deterministic path.
  Future<void> _kebabMenu(int i) => _contextMenu(null, i);

  Future<void> _contextMenu(Offset? globalPos, int i) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final at = globalPos ?? overlay.size.center(Offset.zero);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Semantics(
            identifier: SemanticsIds.protoMenuCopy,
            child: const Text('Copy proposed title'),
          ),
        ),
        PopupMenuItem(
          value: 'apply',
          child: Semantics(
            identifier: SemanticsIds.protoMenuApply,
            child: const Text('Apply proposal'),
          ),
        ),
      ],
    );
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: proposed[i].text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Editing prototype')),
      body: SelectionArea(
        child: Semantics(
          identifier: SemanticsIds.protoTable,
          child: ListView.builder(
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _headerRow(theme);
              }
              final i = index - 1;
              final r = rows[i];
              return GestureDetector(
                onSecondaryTapDown: (d) => _contextMenu(d.globalPosition, i),
                child: Semantics(
                  identifier: SemanticsIds.protoRow(i),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Semantics(
                            identifier: SemanticsIds.protoCellCurrent(i),
                            child: Text(r.currentTitle),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Semantics(
                            identifier: SemanticsIds.protoEdit(i),
                            child: TextField(
                              controller: proposed[i],
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Semantics(
                            identifier: SemanticsIds.protoCellArtist(i),
                            child: Text(r.artist),
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${r.confidence}%',
                            textAlign: TextAlign.end,
                          ),
                        ),
                        Semantics(
                          identifier: SemanticsIds.protoKebab(i),
                          label: 'Row actions',
                          button: true,
                          excludeSemantics: true,
                          onTap: () => _kebabMenu(i),
                          child: IconButton(
                            key: Key(SemanticsIds.protoKebab(i)),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.more_vert, size: 18),
                            onPressed: () => _kebabMenu(i),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _headerRow(ThemeData theme) {
    final style = theme.textTheme.labelLarge;
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Current title', style: style)),
          Expanded(flex: 3, child: Text('Proposed title', style: style)),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: Text('Artist', style: style)),
          SizedBox(width: 48, child: Text('Match', style: style)),
        ],
      ),
    );
  }
}
