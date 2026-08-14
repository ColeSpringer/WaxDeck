import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'playlists_controller.dart';
import 'rule_vocabulary.dart';

/// How a group combines its children. Four modes rather than two
/// because the wire's `not` wraps an `all` or an `any`, and a rule using
/// one used to open read-only for want of a surface.
enum _GroupMode {
  all('all', negated: false, isAny: false),
  any('any', negated: false, isAny: true),
  none('none', negated: true, isAny: true),
  notAll('not-all', negated: true, isAny: false);

  const _GroupMode(this.name, {required this.negated, required this.isAny});

  final String name;

  /// The same four words the rule summary's lead chip draws, so a mode
  /// chosen here and the chip it produces cannot say different things.
  String labelOf(AppLocalizations l10n) => switch (this) {
    _GroupMode.all => l10n.playlistRuleAllOf,
    _GroupMode.any => l10n.playlistRuleAnyOf,
    _GroupMode.none => l10n.playlistRuleNoneOf,
    _GroupMode.notAll => l10n.playlistRuleNotAllOf,
  };

  /// Whether the group is wrapped in a `not` on the wire.
  final bool negated;

  /// Whether the group itself is an `any` (rather than an `all`).
  final bool isAny;

  static _GroupMode byName(String name) =>
      _GroupMode.values.firstWhere((m) => m.name == name);

  static _GroupMode of({required bool negated, required bool isAny}) =>
      _GroupMode.values.firstWhere(
        (m) => m.negated == negated && m.isAny == isAny,
      );
}

/// Mutable draft of one rule node. Groups carry [children]; conditions
/// carry field, op, and one or two values (the second for inTheRange).
class _DraftNode {
  _DraftNode.group({required this.mode, List<_DraftNode>? children})
    : isGroup = true,
      children = children ?? <_DraftNode>[],
      field = '',
      op = '',
      value = '',
      valueHigh = '';

  _DraftNode.condition({
    required this.field,
    required this.op,
    this.value = '',
    this.valueHigh = '',
  }) : isGroup = false,
       mode = _GroupMode.all,
       children = <_DraftNode>[];

  final bool isGroup;
  _GroupMode mode;
  final List<_DraftNode> children;
  String field;
  String op;
  String value;
  String valueHigh;
}

/// One draft sort key.
class _DraftSort {
  _DraftSort(this.field, this.desc);

  String field;
  bool desc;
}

/// Handles by document order, one counter per kind of control: the tree
/// has no stable coordinate a spec could name.
class _Handles {
  var conditions = 0;
  var groups = 0;
}

/// The smart playlist rule editor: nested groups of typed conditions,
/// sort keys, a limit, and a live preview of what the rule matches.
///
/// Creating takes [createName] and [createShared]; editing takes the
/// [editing] playlist and pops with the updated playlist on save.
class RuleEditorScreen extends ConsumerStatefulWidget {
  const RuleEditorScreen({
    super.key,
    this.createName,
    this.createShared = false,
    this.editing,
  }) : assert(
         (createName != null) != (editing != null),
         'either a create name or a playlist to edit',
       );

  final String? createName;
  final bool createShared;
  final Playlist? editing;

  @override
  ConsumerState<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends ConsumerState<RuleEditorScreen> {
  late _DraftNode _root;
  final List<_DraftSort> _sorts = <_DraftSort>[];
  final _limit = TextEditingController();

  /// '' (a count) is a plain member cap; 'random', 'minutes', and
  /// 'megabytes' are the shuffle and budget modes.
  var _limitMode = '';

  /// Non-zero pins a random or budget draw so it repeats each read.
  var _limitSeed = 0;

  var _unsupported = false;
  var _busy = false;
  PlaylistPreview? _preview;
  Timer? _debounce;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    final rule = widget.editing?.rule;
    if (rule == null) {
      _root = _DraftNode.group(mode: _GroupMode.all);
    } else {
      final draft = _draftFromNode(rule.root);
      if (draft == null) {
        _unsupported = true;
        _root = _DraftNode.group(mode: _GroupMode.all);
      } else if (draft.isGroup) {
        _root = draft;
      } else {
        // A bare condition at the root is a valid rule; the editor draws
        // groups, so it becomes a one-child ALL, which evaluates the same.
        _root = _DraftNode.group(
          mode: _GroupMode.all,
          children: <_DraftNode>[draft],
        );
      }
      for (final sort in rule.sorts) {
        _sorts.add(_DraftSort(sort.field, sort.desc));
      }
      if (rule.limit > 0) _limit.text = '${rule.limit}';
      _limitMode = rule.limitMode;
      _limitSeed = rule.limitSeed;
      // A mode with no entry in the picker opens read-only.
      if (!ruleKnownLimitModes.contains(_limitMode)) _unsupported = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedulePreview());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _limit.dispose();
    super.dispose();
  }

  // -- the draft, to and from the wire -------------------------------

  _DraftNode? _draftFromNode(RuleNode node) {
    switch (node.type) {
      case 'all':
      case 'any':
        final children = <_DraftNode>[];
        for (final child in node.nodes) {
          final draft = _draftFromNode(child);
          if (draft == null) return null;
          children.add(draft);
        }
        return _DraftNode.group(
          mode: _GroupMode.of(negated: false, isAny: node.type == 'any'),
          children: children,
        );
      case 'not':
        // Around a group it is one of the four modes; around anything
        // else it becomes a group of one, which evaluates the same.
        final inner = node.node;
        if (inner == null) return null;
        final draft = _draftFromNode(inner);
        if (draft == null) return null;
        if (draft.isGroup && !draft.mode.negated) {
          draft.mode = _GroupMode.of(negated: true, isAny: draft.mode.isAny);
          return draft;
        }
        return _DraftNode.group(
          mode: _GroupMode.none,
          children: <_DraftNode>[draft],
        );
      case 'condition':
        return _DraftNode.condition(
          field: node.field ?? '',
          op: node.op ?? '',
          value: node.values.isNotEmpty ? node.values[0] : (node.value ?? ''),
          valueHigh: node.values.length > 1 ? node.values[1] : '',
        );
      default:
        // An unknown node type has no surface here; the rule opens
        // read-only rather than being silently mangled.
        return null;
    }
  }

  RuleNode _nodeFromDraft(_DraftNode draft) {
    if (draft.isGroup) {
      final group = RuleNode(
        type: draft.mode.isAny ? 'any' : 'all',
        nodes: <RuleNode>[for (final c in draft.children) _nodeFromDraft(c)],
      );
      return draft.mode.negated ? RuleNode(type: 'not', node: group) : group;
    }
    if (ruleUnaryOps.contains(draft.op)) {
      return RuleNode.condition(field: draft.field, op: draft.op);
    }
    if (draft.op == 'inTheRange') {
      return RuleNode.condition(
        field: draft.field,
        op: draft.op,
        values: <String>[draft.value, draft.valueHigh],
      );
    }
    return RuleNode.condition(
      field: draft.field,
      op: draft.op,
      value: draft.value,
    );
  }

  SmartRule _draftRule() => SmartRule(
    root: _nodeFromDraft(_root),
    sorts: <RuleSort>[
      for (final s in _sorts) RuleSort(field: s.field, desc: s.desc),
    ],
    limit: int.tryParse(_limit.text.trim()) ?? 0,
    limitMode: _limitMode,
    limitSeed: _limitSeed,
  );

  // -- what the rule is allowed to be --------------------------------

  bool get _isBudget => _limitMode == 'minutes' || _limitMode == 'megabytes';

  /// The server rejects a sort beside a random draw or a pinned budget,
  /// so the card goes and staged sorts drop rather than 400 on save.
  bool get _sortsBlocked =>
      _limitMode == 'random' || (_isBudget && _limitSeed != 0);

  /// A random draw or a budget needs a positive limit; a count reads
  /// blank as "no limit". Caught here rather than as a 400.
  bool get _limitInvalid {
    if (_limitMode.isEmpty) return false;
    return (int.tryParse(_limit.text.trim()) ?? 0) <= 0;
  }

  // -- editing ---------------------------------------------------------

  void _changed() {
    setState(() {});
    _schedulePreview();
  }

  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final generation = ++_generation;
      try {
        final preview = await ref
            .read(repositoryProvider)
            .previewSmartRule(_draftRule(), limit: 10);
        if (mounted && generation == _generation) {
          setState(() => _preview = preview);
        }
      } on WaxDeckApiException {
        // A draft in progress may be momentarily invalid.
        if (mounted && generation == _generation) {
          setState(() => _preview = null);
        }
      }
    });
  }

  void _addCondition(_DraftNode group, RuleFields vocabulary) {
    final first = vocabulary.fields.firstOrNull;
    if (first == null || first.ops.isEmpty) return;
    group.children.add(
      _DraftNode.condition(field: first.name, op: first.ops.first),
    );
    _changed();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final rule = _draftRule();
      final editing = widget.editing;
      if (editing == null) {
        final created = await ref
            .read(playlistsProvider.notifier)
            .create(
              name: widget.createName!,
              kind: 'smart',
              visibility: widget.createShared ? 'shared' : null,
              rule: rule,
            );
        // Only from the screen that asked: a back gesture during a slow
        // save would otherwise pop whatever it landed on.
        if (mounted) router.pop(created);
      } else {
        final next = await ref
            .read(playlistDetailProvider(editing.pid).notifier)
            .replaceRule(rule);
        if (mounted) router.pop(next);
      }
    } on WaxDeckApiException catch (e) {
      // A rule somebody just wrote, so the server's own refusal: it
      // names the field or the shape it would not take.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(explainRefusal(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- the screen ------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final vocabulary = ref.watch(ruleFieldsProvider);
    final sizeClass = WaxSizeClass.of(context);
    final l10n = context.l10n;
    final name = widget.editing?.name ?? widget.createName!;
    final twoPane = sizeClass.hasSidebar && !_unsupported;

    return WaxScaffold(
      title: l10n.playlistRuleEditorTitle(name),
      largeTitle: false,
      onBack: () => context.leave(fallback: WaxRoute.playlists),
      actions: <Widget>[
        WaxButton(
          label: l10n.commonSave,
          semanticsId: SemanticsIds.ruleSave,
          onPressed: _busy || _unsupported || _limitInvalid
              ? null
              : () => unawaited(_save()),
        ),
      ],
      // The count follows the tree on a phone, where the preview is
      // below the fold. Two-pane has it on screen already.
      bottom: twoPane || _unsupported ? null : _MatchBar(preview: _preview),
      slivers: <Widget>[
        // Before the vocabulary is asked for: no answer to that
        // question would make this rule drawable.
        if (_unsupported)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              title: l10n.playlistRuleReadOnlyTitle,
              message: l10n.playlistRuleReadOnlyMessage,
              glyph: WaxIcons.info,
            ),
          )
        else
          switch (vocabulary) {
            AsyncData(:final value) when twoPane => SliverFillRemaining(
              hasScrollBody: true,
              child: _TwoPane(
                tree: _tree(value, twoPane: true),
                preview: _PreviewPane(preview: _preview),
              ),
            ),
            AsyncData(:final value) => SliverList.list(
              children: <Widget>[
                _tree(value, twoPane: false),
                _PreviewPane(
                  preview: _preview,
                  showCount: false,
                  padding: sizeClass.gutter.add(
                    const EdgeInsets.symmetric(vertical: WaxSpace.s12),
                  ),
                ),
                const SizedBox(height: WaxSpace.s24),
              ],
            ),
            AsyncError(:final error) => SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                title: l10n.playlistRuleVocabularyError,
                message: context.explain(error),
                onRetry: () => ref.invalidate(ruleFieldsProvider),
              ),
            ),
            _ => const SliverFillRemaining(
              hasScrollBody: false,
              child: SkeletonShapes(shape: SkeletonShape.list),
            ),
          },
      ],
    );
  }

  Widget _tree(RuleFields vocabulary, {required bool twoPane}) {
    final handles = _Handles();
    final gutter = WaxSizeClass.of(context).gutter.horizontal / 2;
    return Padding(
      // Directional rather than symmetric, because only the leading edge
      // is the page's. In two panes the trailing edge is the divider,
      // and the preview on the other side of it keeps a panel's own
      // inset - so a symmetric gutter here would sit the tree 32 off a
      // line the preview sits 12 off, which reads as a mistake because
      // it is one.
      padding: EdgeInsetsDirectional.only(
        start: gutter,
        end: twoPane ? WaxSpace.s12 : gutter,
        top: WaxSpace.s12,
        bottom: WaxSpace.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _groupCard(vocabulary, _root, null, handles),
          const SizedBox(height: WaxSpace.s12),
          _sortsCard(vocabulary),
          const SizedBox(height: WaxSpace.s12),
          _limitCard(),
        ],
      ),
    );
  }

  /// One group, and its children indented beneath it.
  Widget _groupCard(
    RuleFields vocabulary,
    _DraftNode group,
    _DraftNode? parent,
    _Handles handles,
  ) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final index = handles.groups++;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilterChipRow(
                  selected: group.mode.name,
                  semanticsId: SemanticsIds.ruleGroupMode(index),
                  chips: <WaxFilterChip>[
                    for (final mode in _GroupMode.values)
                      WaxFilterChip(name: mode.name, label: mode.labelOf(l10n)),
                  ],
                  onSelect: (name) {
                    group.mode = _GroupMode.byName(name);
                    _changed();
                  },
                ),
              ),
              if (parent != null)
                WaxIconButton(
                  glyph: WaxIcons.close,
                  label: l10n.playlistRuleRemoveGroup,
                  size: 16,
                  semanticsId: SemanticsIds.ruleGroupRemove(index),
                  onPressed: () {
                    parent.children.remove(group);
                    _changed();
                  },
                ),
            ],
          ),
          for (final child in group.children)
            Padding(
              padding: const EdgeInsets.only(
                left: WaxSpace.s8,
                top: WaxSpace.s8,
              ),
              child: child.isGroup
                  ? _groupCard(vocabulary, child, group, handles)
                  : _conditionRow(vocabulary, child, group, handles),
            ),
          if (group.children.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s8),
              child: Text(
                group.mode.isAny
                    ? l10n.playlistRuleEmptyAny
                    : l10n.playlistRuleEmptyAll,
                style: WaxType.caption.copyWith(color: colors.textTertiary),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: WaxSpace.s8),
            child: Row(
              children: <Widget>[
                WaxButton(
                  label: l10n.playlistRuleAddCondition,
                  kind: WaxButtonKind.text,
                  icon: WaxIcons.add,
                  // Nothing to add a condition about, so nothing to press.
                  // Only the outermost group carries the handle: the
                  // suite adds a condition to the rule.
                  semanticsId: index == 0
                      ? SemanticsIds.ruleAddCondition
                      : null,
                  onPressed: vocabulary.fields.isEmpty
                      ? null
                      : () => _addCondition(group, vocabulary),
                ),
                WaxButton(
                  label: l10n.playlistRuleAddGroup,
                  kind: WaxButtonKind.text,
                  icon: WaxIcons.add,
                  semanticsId: index == 0 ? SemanticsIds.ruleAddGroup : null,
                  onPressed: () {
                    group.children.add(_DraftNode.group(mode: _GroupMode.any));
                    _changed();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One condition: what to look at, how to compare it, and to what.
  Widget _conditionRow(
    RuleFields vocabulary,
    _DraftNode condition,
    _DraftNode parent,
    _Handles handles,
  ) {
    final l10n = context.l10n;
    final index = handles.conditions++;
    final fields = <String>[
      for (final f in vocabulary.fields) f.name,
      for (final k in vocabulary.tagKeys) '$ruleTagPrefix${k.key}',
    ];
    // A tag key that left the catalogue still draws and revalidates.
    final known = fields.contains(condition.field);
    if (!known) fields.add(condition.field);
    final counts = <String, int>{
      for (final k in vocabulary.tagKeys) '$ruleTagPrefix${k.key}': k.itemCount,
    };
    // An unknown field's operator is kept for the same reason the field
    // is: correcting it would rewrite the rule just by opening it.
    var ops = ruleFieldOps(vocabulary, condition.field);
    if (!ops.contains(condition.op)) {
      if (known) {
        condition.op = ops.first;
      } else {
        ops = <String>[...ops, condition.op];
      }
    }

    return Wrap(
      spacing: WaxSpace.s8,
      runSpacing: WaxSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 200,
          child: _Picker<String>(
            semanticsId: SemanticsIds.ruleField(index),
            label: l10n.playlistRuleFieldPicker,
            value: condition.field,
            entries: <DropdownMenuEntry<String>>[
              for (final field in fields)
                DropdownMenuEntry<String>(
                  value: field,
                  label: counts[field] == null
                      ? ruleFieldLabel(l10n, field)
                      : l10n.playlistRuleFieldWithCount(
                          ruleFieldLabel(l10n, field),
                          counts[field]!,
                        ),
                ),
            ],
            onSelected: (field) {
              condition.field = field;
              condition.op = ruleFieldOps(vocabulary, field).first;
              condition.value = '';
              condition.valueHigh = '';
              _changed();
            },
          ),
        ),
        SizedBox(
          width: 160,
          child: _Picker<String>(
            semanticsId: SemanticsIds.ruleOp(index),
            label: l10n.playlistRuleOpPicker,
            value: condition.op,
            entries: <DropdownMenuEntry<String>>[
              for (final op in ops)
                DropdownMenuEntry<String>(
                  value: op,
                  label: ruleOpLabel(l10n, op),
                ),
            ],
            onSelected: (op) {
              // A relative value is a day count, an absolute one a
              // timestamp; crossing clears rather than keeping a shape.
              if (ruleRelativeOps.contains(op) !=
                  ruleRelativeOps.contains(condition.op)) {
                condition.value = '';
                condition.valueHigh = '';
              }
              condition.op = op;
              _changed();
            },
          ),
        ),
        _valueEditor(vocabulary, condition, parent, index),
        WaxIconButton(
          glyph: WaxIcons.close,
          label: l10n.playlistRuleRemoveCondition,
          size: 16,
          semanticsId: SemanticsIds.ruleConditionRemove(index),
          onPressed: () {
            parent.children.remove(condition);
            _changed();
          },
        ),
      ],
    );
  }

  /// The value control for the condition's field kind.
  Widget _valueEditor(
    RuleFields vocabulary,
    _DraftNode condition,
    _DraftNode parent,
    int index,
  ) {
    if (ruleUnaryOps.contains(condition.op)) return const SizedBox.shrink();
    final l10n = context.l10n;
    final kind = ruleFieldKind(vocabulary, condition.field);
    switch (kind) {
      case 'boolean':
        // Normalised, not just displayed: a fresh condition's empty
        // value would save as neither yes nor no.
        if (condition.value != 'false') condition.value = 'true';
        return SizedBox(
          width: 140,
          child: _Picker<String>(
            semanticsId: SemanticsIds.ruleValue(index),
            label: l10n.playlistRuleValuePicker,
            value: condition.value,
            entries: <DropdownMenuEntry<String>>[
              DropdownMenuEntry<String>(
                value: 'true',
                label: l10n.playlistRuleYes,
              ),
              DropdownMenuEntry<String>(
                value: 'false',
                label: l10n.playlistRuleNo,
              ),
            ],
            onSelected: (value) {
              condition.value = value;
              _changed();
            },
          ),
        );
      case 'mediaType':
        const kinds = <String>['music', 'podcast', 'audiobook'];
        // A media type this client does not know has no picker entry.
        if (!kinds.contains(condition.value)) condition.value = kinds.first;
        return SizedBox(
          width: 160,
          child: _Picker<String>(
            semanticsId: SemanticsIds.ruleValue(index),
            label: l10n.playlistRuleValuePicker,
            value: condition.value,
            entries: <DropdownMenuEntry<String>>[
              for (final kind in kinds)
                DropdownMenuEntry<String>(
                  value: kind,
                  label: l10n.playlistRuleMediaType(kind),
                ),
            ],
            onSelected: (value) {
              condition.value = value;
              _changed();
            },
          ),
        );
      case 'playlist':
        // Static lists only, and every one this caller can see - their
        // own plus shared. A smart list stores no membership for the
        // field to test, and the list being edited is smart by
        // definition, so self-reference is out of the picker for free.
        final lists = <Playlist>[
          for (final pl
              in ref.watch(playlistsProvider).value ?? const <Playlist>[])
            if (!pl.isSmart) pl,
        ];
        if (lists.isEmpty) {
          return Text(
            l10n.playlistRuleNoPlaylists,
            style: WaxType.caption.copyWith(
              color: WaxColors.of(context).textSecondary,
            ),
          );
        }
        // Only a fresh condition gets a default, like the media-type
        // picker. A saved value the fetch does not carry - the list was
        // deleted, converted to smart, unshared, or sits beyond the
        // first page - is kept and shown as unavailable rather than
        // silently repointed at somebody's first list: the server
        // accepts any pl- pid (it matches nothing), and a Save must
        // persist what the person saw, not what build() decided.
        if (condition.value.isEmpty) {
          condition.value = lists.first.pid;
        }
        final known = lists.any((pl) => pl.pid == condition.value);
        return SizedBox(
          width: 200,
          child: _Picker<String>(
            semanticsId: SemanticsIds.ruleValue(index),
            label: l10n.playlistRuleValuePicker,
            value: condition.value,
            entries: <DropdownMenuEntry<String>>[
              for (final pl in lists)
                DropdownMenuEntry<String>(value: pl.pid, label: pl.name),
              if (!known)
                DropdownMenuEntry<String>(
                  value: condition.value,
                  label: l10n.playlistRuleUnavailableList,
                ),
            ],
            onSelected: (value) {
              condition.value = value;
              _changed();
            },
          ),
        );
      case 'date' when ruleRelativeOps.contains(condition.op):
        return _RangeOrSingle(
          low: _valueField(condition, parent, index, low: true, number: true),
          suffix: l10n.playlistRuleDaysSuffix,
        );
      case 'date' when condition.op == 'inTheRange':
        return _RangeOrSingle(
          low: _valueField(condition, parent, index, low: true),
          high: _valueField(condition, parent, index, low: false),
        );
      case 'date':
        return _DateButton(
          value: condition.value,
          semanticsId: SemanticsIds.ruleValue(index),
          onPicked: (picked) {
            condition.value = picked.toUtc().toIso8601String();
            _changed();
          },
        );
      default:
        final number = kind == 'number';
        if (condition.op == 'inTheRange') {
          return _RangeOrSingle(
            low: _valueField(
              condition,
              parent,
              index,
              low: true,
              number: number,
            ),
            high: _valueField(
              condition,
              parent,
              index,
              low: false,
              number: number,
            ),
          );
        }
        return _valueField(condition, parent, index, low: true, number: number);
    }
  }

  Widget _valueField(
    _DraftNode condition,
    _DraftNode parent,
    int index, {
    required bool low,
    bool number = false,
  }) => SizedBox(
    width: 180,
    child: _RuleValueField(
      // Keyed on the condition and its operator: a control that changes
      // shape has to be a new field, not one holding a stale string.
      key: ValueKey<String>(
        '${identityHashCode(condition)}-${condition.op}-$low',
      ),
      initial: low ? condition.value : condition.valueHigh,
      number: number,
      semanticsId: low
          ? SemanticsIds.ruleValue(index)
          : SemanticsIds.ruleValueHigh(index),
      onChanged: (value) {
        if (low) {
          condition.value = value;
        } else {
          condition.valueHigh = value;
        }
        _schedulePreview();
      },
      // Enter starts the next condition, so a rule can be written
      // without reaching for a pointer between lines.
      onSubmitted: () {
        final vocabulary = ref.read(ruleFieldsProvider).value;
        if (vocabulary != null) _addCondition(parent, vocabulary);
      },
    ),
  );

  /// The order the members come out in, where the rule is allowed one.
  Widget _sortsCard(RuleFields vocabulary) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    if (_sortsBlocked) {
      return _Card(
        child: Text(
          _limitMode == 'random'
              ? l10n.playlistRuleRandomOrder
              : l10n.playlistRulePinnedOrder,
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
      );
    }
    final sortable = <String>[
      for (final f in vocabulary.fields)
        if (f.sortable) f.name,
    ];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.playlistRuleOrderBy,
            style: WaxType.overline.copyWith(color: colors.textTertiary),
          ),
          for (var i = 0; i < _sorts.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: WaxSpace.s8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _Picker<String>(
                      semanticsId: SemanticsIds.ruleSortField(i),
                      label: l10n.playlistRuleFieldPicker,
                      // Corrected rather than drawn over: a sort on a
                      // field this vocabulary no longer offers would
                      // otherwise show an order the save does not send.
                      value: _sortField(sortable, i),
                      entries: <DropdownMenuEntry<String>>[
                        for (final field in sortable)
                          DropdownMenuEntry<String>(
                            value: field,
                            label: ruleFieldLabel(l10n, field),
                          ),
                      ],
                      onSelected: (field) {
                        _sorts[i].field = field;
                        _changed();
                      },
                    ),
                  ),
                  const SizedBox(width: WaxSpace.s8),
                  WaxButton(
                    label: _sorts[i].desc
                        ? l10n.playlistRuleHighestFirst
                        : l10n.playlistRuleLowestFirst,
                    kind: WaxButtonKind.text,
                    semanticsId: SemanticsIds.ruleSortDirection(i),
                    onPressed: () {
                      _sorts[i].desc = !_sorts[i].desc;
                      _changed();
                    },
                  ),
                  WaxIconButton(
                    glyph: WaxIcons.close,
                    label: l10n.playlistRuleRemoveSort,
                    size: 16,
                    semanticsId: SemanticsIds.ruleSortRemove(i),
                    onPressed: () {
                      _sorts.removeAt(i);
                      _changed();
                    },
                  ),
                ],
              ),
            ),
          // Four is the contract's cap.
          if (_sorts.length < 4)
            Align(
              alignment: Alignment.centerLeft,
              child: WaxButton(
                label: l10n.playlistRuleAddSort,
                kind: WaxButtonKind.text,
                icon: WaxIcons.add,
                semanticsId: SemanticsIds.ruleAddSort,
                onPressed: sortable.isEmpty
                    ? null
                    : () {
                        _sorts.add(_DraftSort(sortable.first, false));
                        _changed();
                      },
              ),
            ),
        ],
      ),
    );
  }

  /// The field sort [i] is on, corrected to one this vocabulary offers.
  String _sortField(List<String> sortable, int i) {
    if (sortable.isEmpty || sortable.contains(_sorts[i].field)) {
      return _sorts[i].field;
    }
    return _sorts[i].field = sortable.first;
  }

  /// How much of what matches actually joins the list.
  Widget _limitCard() {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            l10n.playlistRuleLimitHeading,
            style: WaxType.overline.copyWith(color: colors.textTertiary),
          ),
          const SizedBox(height: WaxSpace.s8),
          Wrap(
            spacing: WaxSpace.s8,
            runSpacing: WaxSpace.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 180,
                child: _Picker<String>(
                  semanticsId: SemanticsIds.ruleLimitMode,
                  label: l10n.playlistRuleLimitTake,
                  value: _limitMode,
                  entries: <DropdownMenuEntry<String>>[
                    DropdownMenuEntry<String>(
                      value: '',
                      label: l10n.playlistRuleLimitByCount,
                    ),
                    DropdownMenuEntry<String>(
                      value: 'random',
                      label: l10n.playlistRuleLimitAtRandom,
                    ),
                    DropdownMenuEntry<String>(
                      value: 'minutes',
                      label: l10n.playlistRuleLimitByMinutes,
                    ),
                    DropdownMenuEntry<String>(
                      value: 'megabytes',
                      label: l10n.playlistRuleLimitBySize,
                    ),
                  ],
                  onSelected: (mode) {
                    setState(() {
                      _limitMode = mode;
                      if (_limitMode.isEmpty) _limitSeed = 0;
                      // A mode whose order the draw supplies cannot also
                      // carry a sort order; drop any staged sorts.
                      if (_sortsBlocked) _sorts.clear();
                    });
                    _schedulePreview();
                  },
                ),
              ),
              SizedBox(
                width: 140,
                child: _RuleValueField(
                  controller: _limit,
                  number: true,
                  hint: _limitMode.isEmpty
                      ? l10n.playlistRuleLimitNoLimit
                      : l10n.playlistRuleLimitRequired,
                  label: ruleLimitUnit(l10n, _limitMode),
                  semanticsId: SemanticsIds.ruleLimitValue,
                  onChanged: (_) => _changed(),
                ),
              ),
              Text(
                ruleLimitUnit(l10n, _limitMode),
                style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          if (_limitMode.isNotEmpty)
            WaxSettingRow(
              key: const Key(SemanticsIds.ruleLimitSeed),
              title: l10n.playlistRuleSeedTitle,
              help: l10n.playlistRuleSeedHelp,
              control: WaxSwitch(
                value: _limitSeed != 0,
                label: l10n.playlistRuleSeedTitle,
                semanticsId: SemanticsIds.ruleLimitSeed,
                onChanged: (pinned) {
                  setState(() {
                    _limitSeed = pinned ? 1 : 0;
                    // Pinning a budget's order drops its sort keys.
                    if (_sortsBlocked) _sorts.clear();
                  });
                  _schedulePreview();
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The tree beside its preview, at sidebar width and wider.
class _TwoPane extends StatelessWidget {
  const _TwoPane({required this.tree, required this.preview});

  final Widget tree;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Each pane scrolls itself: a long tree must not push the count
        // off screen.
        Expanded(child: SingleChildScrollView(child: tree)),
        VerticalDivider(width: 1, color: colors.hairline),
        SizedBox(
          width: WaxShellMetrics.rightPanelWidth,
          child: SingleChildScrollView(child: preview),
        ),
      ],
    );
  }
}

/// What the rule matches right now: the count, then the first page of it.
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.preview,
    this.showCount = true,
    this.padding = const EdgeInsets.all(WaxSpace.s12),
  });

  final PlaylistPreview? preview;

  /// False where the count is in the sticky bar instead.
  final bool showCount;

  /// The default is a side panel's own inset, which is where this pane
  /// spends most of its life. Below the tree in one pane it is page
  /// content instead, and the caller hands it the gutter so its rows
  /// line up with the cards above them rather than sitting four pixels
  /// inside them.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final items = preview?.items ?? const <ItemSummary>[];
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (showCount)
            Semantics(
              identifier: SemanticsIds.rulePreviewTotal,
              liveRegion: true,
              child: Text(
                matchLabel(l10n, preview),
                style: WaxType.headline.copyWith(color: colors.textPrimary),
              ),
            )
          else
            Text(
              l10n.playlistRuleFirstMatches,
              style: WaxType.overline.copyWith(color: colors.textTertiary),
            ),
          const SizedBox(height: WaxSpace.s8),
          if (preview == null)
            Text(
              l10n.playlistRuleWorking,
              style: WaxType.bodySmall.copyWith(color: colors.textTertiary),
            )
          else if (items.isEmpty)
            Text(
              l10n.playlistRuleNoMatches,
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
            )
          else
            for (final item in items)
              MediaListRow(
                data: MediaTileData(
                  title: item.title,
                  subtitle: item.artist,
                  trailingText: item.durationMs > 0
                      ? formatTimecode(Duration(milliseconds: item.durationMs))
                      : null,
                ),
              ),
        ],
      ),
    );
  }
}

/// The sticky count on a phone, where the preview list is below the fold.
class _MatchBar extends StatelessWidget {
  const _MatchBar({required this.preview});

  final PlaylistPreview? preview;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(
          top: BorderSide(color: colors.hairline, width: layout.hairlineWidth),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WaxSpace.s16,
            vertical: WaxSpace.s12,
          ),
          child: Semantics(
            identifier: SemanticsIds.rulePreviewTotal,
            liveRegion: true,
            child: Text(
              matchLabel(context.l10n, preview),
              style: WaxType.titleItem.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Matches 214 items", or that the answer is still being worked out.
String matchLabel(AppLocalizations l10n, PlaylistPreview? preview) =>
    preview == null
    ? l10n.playlistRulePreviewPending
    : l10n.playlistRuleMatches(preview.total);

/// The editor's card surface.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Container(
      padding: const EdgeInsets.all(WaxSpace.s12),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: WaxRadius.card,
        border: Border.all(color: colors.hairline),
      ),
      child: child,
    );
  }
}

/// A labelled value picker. Material's, annotated: the design system
/// has no picker, and a field list of thirty is not a chip row.
class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.entries,
    required this.onSelected,
    required this.semanticsId,
  });

  final String label;
  final T value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;
  final String semanticsId;

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: semanticsId,
    child: DropdownMenu<T>(
      // The locale is part of the key: DropdownMenu rewrites its own
      // field only when `initialSelection` changes, so new entry labels
      // leave the closed field reading the old language.
      key: Key('$semanticsId-${context.l10n.localeName}'),
      initialSelection: value,
      label: Text(label),
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      dropdownMenuEntries: entries,
      onSelected: (chosen) {
        if (chosen != null) onSelected(chosen);
      },
    ),
  );
}

/// A date value: the picked day, or an invitation to pick one.
class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.value,
    required this.onPicked,
    required this.semanticsId,
  });

  final String value;
  final ValueChanged<DateTime> onPicked;
  final String semanticsId;

  @override
  Widget build(BuildContext context) {
    final current = DateTime.tryParse(value);
    final l10n = context.l10n;
    return WaxButton(
      label: current == null
          ? l10n.playlistRulePickDate
          : l10n.formatDate(current),
      kind: WaxButtonKind.tonal,
      icon: WaxIcons.recent,
      semanticsId: semanticsId,
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: current ?? DateTime.now(),
          firstDate: DateTime(1970),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPicked(picked);
      },
    );
  }
}

/// A range, or one field with a unit after it.
class _RangeOrSingle extends StatelessWidget {
  const _RangeOrSingle({required this.low, this.high, this.suffix});

  final Widget low;
  final Widget? high;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        low,
        if (high != null) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s8),
            child: Text(
              context.l10n.playlistRuleAnd,
              style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
          high!,
        ],
        if (suffix != null) ...<Widget>[
          const SizedBox(width: WaxSpace.s8),
          Text(
            suffix!,
            style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// A value input owning its controller, so a rebuild of the tree above
/// never resets the caret.
class _RuleValueField extends StatefulWidget {
  const _RuleValueField({
    super.key,
    this.initial = '',
    this.controller,
    this.label,
    this.hint,
    this.number = false,
    this.semanticsId,
    this.onChanged,
    this.onSubmitted,
  });

  final String initial;

  /// Supplied where the caller owns the text (the limit).
  final TextEditingController? controller;

  /// Null takes the general word for a condition's value; the limit
  /// field passes the unit it counts instead.
  final String? label;

  final String? hint;
  final bool number;
  final String? semanticsId;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  @override
  State<_RuleValueField> createState() => _RuleValueFieldState();
}

class _RuleValueFieldState extends State<_RuleValueField> {
  TextEditingController? _owned;

  TextEditingController get _controller =>
      widget.controller ??
      (_owned ??= TextEditingController(text: widget.initial));

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WaxTextField(
    label: widget.label ?? context.l10n.playlistRuleValuePicker,
    hint: widget.hint,
    controller: _controller,
    textInputAction: TextInputAction.done,
    semanticsId: widget.semanticsId,
    onChanged: widget.onChanged,
    onSubmitted: (_) => widget.onSubmitted?.call(),
  );
}
