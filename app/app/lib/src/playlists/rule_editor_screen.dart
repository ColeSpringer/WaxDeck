import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';

import '../providers.dart';
import 'playlists_controller.dart';

/// The smart playlist rule editor: nested ALL and ANY groups of typed
/// conditions, sort keys, a member limit, and a live match preview.
/// Creating takes [createName] and [createShared]; editing takes the
/// [editing] playlist and pops with the reissued successor on save.
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

/// Mutable draft of one rule node. Groups carry [children]; conditions
/// carry field, op, and one or two values (the second for inTheRange).
class _DraftNode {
  _DraftNode.group({required this.any, List<_DraftNode>? children})
    : isGroup = true,
      children = children ?? [],
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
       any = false,
       children = [];

  final bool isGroup;
  bool any;
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

/// Operators tag fields accept; the vocabulary endpoint documents the
/// set once instead of repeating it per key.
const _tagOps = [
  'is',
  'isNot',
  'contains',
  'startsWith',
  'endsWith',
  'isPresent',
  'isMissing',
];

/// Operators that take no value.
const _presenceOps = {'isPresent', 'isMissing'};

class _RuleEditorScreenState extends ConsumerState<RuleEditorScreen> {
  late _DraftNode _root;
  final List<_DraftSort> _sorts = [];
  final _limitController = TextEditingController();
  var _unsupported = false;
  var _busy = false;
  PlaylistPreview? _preview;
  Timer? _previewDebounce;
  var _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    final rule = widget.editing?.rule;
    if (rule == null) {
      _root = _DraftNode.group(any: false);
    } else {
      final draft = _draftFromNode(rule.root);
      if (draft == null || !draft.isGroup) {
        _unsupported = draft == null;
        _root = draft ?? _DraftNode.group(any: false);
        if (draft != null && !draft.isGroup) {
          _root = _DraftNode.group(any: false, children: [draft]);
        }
      } else {
        _root = draft;
      }
      for (final s in rule.sorts) {
        _sorts.add(_DraftSort(s.field, s.desc));
      }
      if (rule.limit > 0) _limitController.text = '${rule.limit}';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedulePreview());
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _limitController.dispose();
    super.dispose();
  }

  _DraftNode? _draftFromNode(RuleNode node) {
    switch (node.type) {
      case 'all':
      case 'any':
        final children = <_DraftNode>[];
        for (final c in node.nodes) {
          final child = _draftFromNode(c);
          if (child == null) return null;
          children.add(child);
        }
        return _DraftNode.group(any: node.type == 'any', children: children);
      case 'condition':
        return _DraftNode.condition(
          field: node.field ?? '',
          op: node.op ?? '',
          value: node.values.isNotEmpty ? node.values[0] : (node.value ?? ''),
          valueHigh: node.values.length > 1 ? node.values[1] : '',
        );
      default:
        // The editor has no surface for `not` or unknown node types;
        // such rules open read-only rather than being silently mangled.
        return null;
    }
  }

  RuleNode _nodeFromDraft(_DraftNode draft) {
    if (draft.isGroup) {
      return RuleNode(
        type: draft.any ? 'any' : 'all',
        nodes: [for (final c in draft.children) _nodeFromDraft(c)],
      );
    }
    if (_presenceOps.contains(draft.op)) {
      return RuleNode.condition(field: draft.field, op: draft.op);
    }
    if (draft.op == 'inTheRange') {
      return RuleNode.condition(
        field: draft.field,
        op: draft.op,
        values: [draft.value, draft.valueHigh],
      );
    }
    return RuleNode.condition(
      field: draft.field,
      op: draft.op,
      value: draft.value,
    );
  }

  SmartRule _draftRule() {
    return SmartRule(
      root: _nodeFromDraft(_root),
      sorts: [for (final s in _sorts) RuleSort(field: s.field, desc: s.desc)],
      limit: int.tryParse(_limitController.text.trim()) ?? 0,
    );
  }

  void _changed() {
    setState(() {});
    _schedulePreview();
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 500), () async {
      final generation = ++_previewGeneration;
      try {
        final preview = await ref
            .read(repositoryProvider)
            .previewSmartRule(_draftRule(), limit: 5);
        if (mounted && generation == _previewGeneration) {
          setState(() => _preview = preview);
        }
      } on WaxDeckApiException {
        // An in-progress draft may be momentarily invalid (an empty
        // value under a typed field); the preview simply waits for the
        // next edit.
        if (mounted && generation == _previewGeneration) {
          setState(() => _preview = null);
        }
      }
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
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
        navigator.pop(created);
      } else {
        final next = await ref
            .read(playlistDetailProvider(editing.pid).notifier)
            .replaceRule(rule);
        navigator.pop(next);
      }
    } on WaxDeckApiException catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vocabulary = ref.watch(ruleFieldsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.editing == null
              ? 'Rules: ${widget.createName}'
              : 'Rules: ${widget.editing!.name}',
        ),
        actions: [
          Semantics(
            identifier: 'rule-save',
            label: 'Save rules',
            button: true,
            child: TextButton(
              key: const Key('rule-save'),
              onPressed: _busy || _unsupported ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: switch (vocabulary) {
        AsyncData(:final value) => _body(context, value),
        AsyncError() => const Center(
          child: Text('Could not load the rule vocabulary'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(BuildContext context, RuleFields vocabulary) {
    if (_unsupported) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'This rule uses features the editor does not support yet, '
            'so it opens read-only.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final preview = _preview;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _groupCard(context, vocabulary, _root, null),
        const SizedBox(height: 12),
        _sortsCard(context, vocabulary),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Expanded(child: Text('Limit to')),
                SizedBox(
                  width: 96,
                  child: TextField(
                    key: const Key('rule-limit-field'),
                    controller: _limitController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'no limit'),
                    onChanged: (_) => _changed(),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('items'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview == null
                      ? 'Preview pending'
                      : 'Matches ${preview.total} items',
                  key: const Key('rule-preview-total'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (preview != null)
                  for (final item in preview.items)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        item.artist == null
                            ? item.title
                            : '${item.title} (${item.artist})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _groupCard(
    BuildContext context,
    RuleFields vocabulary,
    _DraftNode group,
    _DraftNode? parent,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('ALL')),
                    ButtonSegment(value: true, label: Text('ANY')),
                  ],
                  selected: {group.any},
                  onSelectionChanged: (selection) {
                    group.any = selection.first;
                    _changed();
                  },
                ),
                const Spacer(),
                if (parent != null)
                  IconButton(
                    tooltip: 'Remove group',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      parent.children.remove(group);
                      _changed();
                    },
                  ),
              ],
            ),
            for (final child in group.children)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: child.isGroup
                    ? _groupCard(context, vocabulary, child, group)
                    : _conditionRow(context, vocabulary, child, group),
              ),
            Row(
              children: [
                Semantics(
                  identifier: 'rule-add-condition',
                  label: 'Add condition',
                  button: true,
                  child: TextButton.icon(
                    key: const Key('rule-add-condition'),
                    icon: const Icon(Icons.add),
                    label: const Text('Condition'),
                    onPressed: () {
                      final first = vocabulary.fields.first;
                      group.children.add(
                        _DraftNode.condition(
                          field: first.name,
                          op: first.ops.first,
                        ),
                      );
                      _changed();
                    },
                  ),
                ),
                TextButton.icon(
                  key: const Key('rule-add-group'),
                  icon: const Icon(Icons.add),
                  label: const Text('Group'),
                  onPressed: () {
                    group.children.add(_DraftNode.group(any: true));
                    _changed();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<String> _opsFor(RuleFields vocabulary, String field) {
    if (field.startsWith('tag.')) return _tagOps;
    for (final f in vocabulary.fields) {
      if (f.name == field) return f.ops;
    }
    return const ['is'];
  }

  String _kindFor(RuleFields vocabulary, String field) {
    if (field.startsWith('tag.')) return 'text';
    for (final f in vocabulary.fields) {
      if (f.name == field) return f.kind;
    }
    return 'text';
  }

  Widget _conditionRow(
    BuildContext context,
    RuleFields vocabulary,
    _DraftNode condition,
    _DraftNode parent,
  ) {
    final fieldNames = [
      for (final f in vocabulary.fields) f.name,
      for (final k in vocabulary.tagKeys) 'tag.${k.key}',
    ];
    if (!fieldNames.contains(condition.field)) {
      // A tag key that vanished from the catalog still renders; saving
      // it revalidates server-side.
      fieldNames.add(condition.field);
    }
    final ops = _opsFor(vocabulary, condition.field);
    if (!ops.contains(condition.op)) condition.op = ops.first;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: DropdownButton<String>(
            key: const Key('rule-field-select'),
            isExpanded: true,
            value: condition.field,
            items: [
              for (final name in fieldNames)
                DropdownMenuItem(value: name, child: Text(name)),
            ],
            onChanged: (v) {
              if (v == null) return;
              condition.field = v;
              condition.op = _opsFor(vocabulary, v).first;
              condition.value = '';
              condition.valueHigh = '';
              _changed();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: DropdownButton<String>(
            key: const Key('rule-op-select'),
            isExpanded: true,
            value: condition.op,
            items: [
              for (final op in ops)
                DropdownMenuItem(value: op, child: Text(op)),
            ],
            onChanged: (v) {
              if (v == null) return;
              condition.op = v;
              _changed();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(flex: 3, child: _valueEditor(context, vocabulary, condition)),
        IconButton(
          tooltip: 'Remove condition',
          icon: const Icon(Icons.close),
          onPressed: () {
            parent.children.remove(condition);
            _changed();
          },
        ),
      ],
    );
  }

  Widget _valueEditor(
    BuildContext context,
    RuleFields vocabulary,
    _DraftNode condition,
  ) {
    if (_presenceOps.contains(condition.op)) {
      return const SizedBox.shrink();
    }
    final kind = _kindFor(vocabulary, condition.field);
    switch (kind) {
      case 'boolean':
        return DropdownButton<String>(
          isExpanded: true,
          value: condition.value == 'false' ? 'false' : 'true',
          items: const [
            DropdownMenuItem(value: 'true', child: Text('yes')),
            DropdownMenuItem(value: 'false', child: Text('no')),
          ],
          onChanged: (v) {
            condition.value = v ?? 'true';
            _changed();
          },
        );
      case 'mediaType':
        final value =
            ['music', 'podcast', 'audiobook'].contains(condition.value)
            ? condition.value
            : 'music';
        condition.value = value;
        return DropdownButton<String>(
          isExpanded: true,
          value: value,
          items: const [
            DropdownMenuItem(value: 'music', child: Text('music')),
            DropdownMenuItem(value: 'podcast', child: Text('podcast')),
            DropdownMenuItem(value: 'audiobook', child: Text('audiobook')),
          ],
          onChanged: (v) {
            condition.value = v ?? 'music';
            _changed();
          },
        );
      case 'date':
        return _dateEditor(context, condition);
      default:
        if (condition.op == 'inTheRange') {
          return Row(
            children: [
              Expanded(child: _valueField(condition, low: true)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('to'),
              ),
              Expanded(child: _valueField(condition, low: false)),
            ],
          );
        }
        return _valueField(condition, low: true);
    }
  }

  Widget _valueField(_DraftNode condition, {required bool low}) {
    return _RuleValueField(
      key: ValueKey('${identityHashCode(condition)}-${condition.op}-$low'),
      initial: low ? condition.value : condition.valueHigh,
      onChanged: (v) {
        if (low) {
          condition.value = v;
        } else {
          condition.valueHigh = v;
        }
        _schedulePreview();
      },
    );
  }

  Widget _dateEditor(BuildContext context, _DraftNode condition) {
    final current = DateTime.tryParse(condition.value);
    if (condition.op == 'inTheRange') {
      // Range dates fall back to two text fields; the common date rules
      // are before and after.
      return Row(
        children: [
          Expanded(child: _valueField(condition, low: true)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('to'),
          ),
          Expanded(child: _valueField(condition, low: false)),
        ],
      );
    }
    return OutlinedButton(
      key: const Key('rule-date-pick'),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: current ?? DateTime.now(),
          firstDate: DateTime(1970),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          condition.value = picked.toUtc().toIso8601String();
          _changed();
        }
      },
      child: Text(
        current == null
            ? 'Pick date'
            : current.toLocal().toString().split(' ').first,
      ),
    );
  }

  Widget _sortsCard(BuildContext context, RuleFields vocabulary) {
    final sortable = [
      for (final f in vocabulary.fields)
        if (f.sortable) f.name,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Order by', style: Theme.of(context).textTheme.titleSmall),
            for (final sort in _sorts)
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: sortable.contains(sort.field)
                          ? sort.field
                          : sortable.first,
                      items: [
                        for (final name in sortable)
                          DropdownMenuItem(value: name, child: Text(name)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        sort.field = v;
                        _changed();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      sort.desc = !sort.desc;
                      _changed();
                    },
                    child: Text(sort.desc ? 'descending' : 'ascending'),
                  ),
                  IconButton(
                    tooltip: 'Remove sort',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _sorts.remove(sort);
                      _changed();
                    },
                  ),
                ],
              ),
            if (_sorts.length < 4)
              TextButton.icon(
                key: const Key('rule-add-sort'),
                icon: const Icon(Icons.add),
                label: const Text('Sort key'),
                onPressed: () {
                  _sorts.add(_DraftSort(sortable.first, false));
                  _changed();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// A debounced free-text value input that keeps its own controller, so
/// rebuilds of the surrounding tree never reset the caret.
class _RuleValueField extends StatefulWidget {
  const _RuleValueField({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_RuleValueField> createState() => _RuleValueFieldState();
}

class _RuleValueFieldState extends State<_RuleValueField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('rule-value-field'),
      controller: _controller,
      decoration: const InputDecoration(hintText: 'value'),
      onChanged: widget.onChanged,
    );
  }
}
