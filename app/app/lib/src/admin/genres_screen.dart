import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'admin_console.dart';
import 'admin_providers.dart';

/// The canonical genre vocabulary: the tree every scanned genre folds
/// onto, and the aliases that reach it.
///
/// Two panes where there is room: the tree on the left, one genre's
/// detail on the right. The edits are local until they are saved, so
/// moving a genre and renaming it is one write rather than two catalog
/// re-sweeps - the contract replaces the whole vocabulary in one call
/// and rewinds the normalization sweeper afterwards, and every
/// intermediate save would rewind it again.
class GenreTreeScreen extends ConsumerStatefulWidget {
  const GenreTreeScreen({super.key});

  @override
  ConsumerState<GenreTreeScreen> createState() => _GenreTreeScreenState();
}

class _GenreTreeScreenState extends ConsumerState<GenreTreeScreen> {
  /// The working copy. Null until the stored tree lands.
  List<GenreNode>? _draft;

  /// The name of the genre the detail pane is editing.
  String? _selected;

  /// Bumped only when a *different* genre is picked, never when the one
  /// on screen is renamed. The detail pane is keyed by it, so renaming
  /// keeps the same State and the caret stays where the typing is -
  /// which is what lets the name commit on every keystroke instead of
  /// waiting for a key nobody presses.
  int _selectionEpoch = 0;

  void _select(String? name) {
    setState(() {
      _selected = name;
      _selectionEpoch++;
    });
  }

  bool _dirty = false;
  bool _busy = false;

  void _adopt(GenreTree tree) {
    _draft = List<GenreNode>.of(tree.genres);
    _dirty = false;
  }

  List<GenreNode> get _genres => _draft ?? const <GenreNode>[];

  GenreNode? get _current {
    for (final node in _genres) {
      if (node.name == _selected) return node;
    }
    return null;
  }

  /// Top-level genres, each followed by what groups under it. The
  /// contract already answers in this order; the draft may not be, once
  /// a genre has been re-parented locally.
  List<GenreNode> get _ordered {
    final parents = _genres.where((g) => g.parent == null).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final out = <GenreNode>[];
    for (final parent in parents) {
      out.add(parent);
      final children = _genres.where((g) => g.parent == parent.name).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      out.addAll(children);
    }
    // A genre whose parent is not in the tree would otherwise vanish from
    // the editor while still being sent back on save.
    final placed = out.map((g) => g.name).toSet();
    out.addAll(_genres.where((g) => !placed.contains(g.name)));
    return out;
  }

  void _mutate(void Function() change) {
    setState(() {
      change();
      _dirty = true;
    });
  }

  void _add() {
    var name = 'New genre';
    var n = 2;
    while (_genres.any((g) => g.name.toLowerCase() == name.toLowerCase())) {
      name = 'New genre $n';
      n++;
    }
    _mutate(() {
      _draft = <GenreNode>[..._genres, GenreNode(name: name)];
      _selected = name;
      _selectionEpoch++;
    });
  }

  /// Whether [candidate] is already some other genre's name. The tree
  /// is keyed by name - a parent reference is a name, and so is the
  /// alias resolution - so two nodes sharing one would merge their
  /// children on the next edit and post a vocabulary the server cannot
  /// resolve one way.
  bool _nameTaken(String candidate, GenreNode except) {
    final needle = candidate.toLowerCase();
    for (final node in _genres) {
      if (node.name == except.name) continue;
      if (node.name.toLowerCase() == needle) return true;
    }
    return false;
  }

  void _replace(GenreNode was, GenreNode now) {
    if (now.name != was.name && _nameTaken(now.name, was)) return;
    _mutate(() {
      _draft = <GenreNode>[
        for (final node in _genres)
          if (node.name == was.name)
            now
          // A rename carries its children with it: a parent reference is
          // by name, so leaving them pointing at the old spelling would
          // orphan them silently.
          else if (node.parent == was.name)
            node.copyWith(parent: now.name)
          else
            node,
      ];
      if (_selected == was.name) _selected = now.name;
    });
  }

  void _remove(GenreNode node) {
    _mutate(() {
      _draft = <GenreNode>[
        for (final other in _genres)
          if (other.name != node.name)
            // What grouped under a removed parent comes up a level
            // rather than disappearing with it.
            other.parent == node.name
                ? other.copyWith(clearParent: true)
                : other,
      ];
      if (_selected == node.name) _selected = null;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(genreTreeProvider.notifier).save(_genres);
      if (!mounted) return;
      setState(() => _dirty = false);
      messenger.show('Genre tree saved');
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Clearing the override is an empty vocabulary, which is the
  /// contract's own revert: there is no separate endpoint, and sending
  /// the shipped list back would store a custom tree identical to the
  /// default and stop tracking it.
  Future<void> _revert() async {
    final confirmed = await showTypedConfirm(
      context,
      title: 'Revert to the default tree?',
      message:
          'Your genre vocabulary is replaced by the one WaxDeck ships. '
          'Aliases you added are lost, and the catalog re-normalizes onto '
          'the default.',
      confirmWord: 'REVERT',
      confirmLabel: 'Revert',
      fieldSemanticsId: SemanticsIds.confirmField,
      confirmSemanticsId: SemanticsIds.confirmAccept,
      cancelSemanticsId: SemanticsIds.confirmCancel,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(genreTreeProvider.notifier).save(const <GenreNode>[]);
      if (!mounted) return;
      setState(() {
        _draft = null;
        _selected = null;
        _dirty = false;
      });
      messenger.show('Back on the default genre tree');
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _normalize({required bool dryRun}) async {
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      await ref.read(repositoryProvider).normalizeGenres(dryRun: dryRun);
      if (!mounted) return;
      messenger.show(
        dryRun
            ? 'Dry run started; the task report says what would change'
            : 'Normalizing the catalog',
        actionLabel: 'Tasks',
        actionSemanticsId: SemanticsIds.adminAction('genre-tasks'),
        onAction: () => context.push(WaxRoute.tasks),
      );
    } on WaxDeckApiException catch (error) {
      messenger.show(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sizeClass = WaxSizeClass.of(context);
    final tree = ref.watch(genreTreeProvider);
    // Adopting inside build rather than through a listener: the draft is
    // this screen's own state, and the stored tree only arrives once
    // unless a save replaces it, which sets the draft itself.
    if (_draft == null && tree.hasValue) _adopt(tree.requireValue);

    return WaxScaffold(
      title: 'Genre tree',
      largeTitle: false,
      semanticsId: SemanticsIds.adminGenres,
      onBack: adminBack(context),
      actions: <Widget>[
        WaxButton(
          label: 'Save',
          kind: WaxButtonKind.text,
          semanticsId: SemanticsIds.genreSave,
          onPressed: _dirty && !_busy ? _save : null,
        ),
      ],
      body: switch (tree) {
        AsyncError(:final error) => Padding(
          padding: sizeClass.gutter,
          child: ErrorState(
            title: 'Could not load the genre tree',
            message: error is WaxDeckApiException
                ? error.message
                : 'Something went wrong reading it.',
            onRetry: () => ref.invalidate(genreTreeProvider),
          ),
        ),
        AsyncData(:final value) => Padding(
          padding: sizeClass.gutter.add(
            const EdgeInsets.only(bottom: WaxSpace.s32),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Header(
                source: value.source,
                busy: _busy,
                onRevert: value.isDefault ? null : _revert,
                onNormalize: (dryRun) => _normalize(dryRun: dryRun),
              ),
              const SizedBox(height: WaxSpace.s16),
              // No IntrinsicHeight around this: it would bound both
              // panes to the taller one's intrinsic height, and the pane
              // that is an empty state does not fit in what the other
              // asks for. Each column takes the height it needs and the
              // page scrolls.
              if (sizeClass.hasSidebar)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(flex: 3, child: _tree()),
                    const SizedBox(width: WaxSpace.s24),
                    Expanded(flex: 2, child: _detail()),
                  ],
                )
              else ...<Widget>[
                _tree(),
                const SizedBox(height: WaxSpace.s24),
                _detail(),
              ],
            ],
          ),
        ),
        _ => const SkeletonShapes(shape: SkeletonShape.list),
      },
    );
  }

  Widget _tree() {
    final colors = WaxColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: 'Vocabulary',
          actionLabel: 'Add genre',
          semanticsId: SemanticsIds.genreAdd,
          onAction: _busy ? null : _add,
        ),
        if (_genres.isEmpty)
          const EmptyState(
            glyph: WaxIcons.filter,
            title: 'No genres',
            message: 'Add one, or revert to the tree WaxDeck ships.',
          )
        else
          Container(
            decoration: BoxDecoration(
              borderRadius: WaxRadius.card,
              border: Border.all(color: colors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (final node in _ordered)
                  _GenreRow(
                    node: node,
                    selected: node.name == _selected,
                    onTap: () => _select(node.name),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _detail() {
    final node = _current;
    if (node == null) {
      return const EmptyState(
        glyph: WaxIcons.info,
        title: 'Pick a genre',
        message: 'Its name, its parent, and its aliases are edited here.',
      );
    }
    return _GenreDetail(
      // Keyed by the selection rather than by the name, so switching
      // genres rebuilds the fields while renaming the current one does
      // not throw away the text being typed into them.
      key: ValueKey<int>(_selectionEpoch),
      node: node,
      isNameTaken: (candidate) => _nameTaken(candidate, node),
      parents: <String>[
        for (final other in _genres)
          if (other.parent == null && other.name != node.name) other.name,
      ],
      hasChildren: _genres.any((g) => g.parent == node.name),
      onChanged: (updated) => _replace(node, updated),
      onDelete: () => _remove(node),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.source,
    required this.busy,
    required this.onRevert,
    required this.onNormalize,
  });

  final String source;
  final bool busy;
  final VoidCallback? onRevert;
  final void Function(bool dryRun) onNormalize;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          source == 'default'
              ? 'Running on the vocabulary WaxDeck ships. Editing it stores '
                    'a tree of your own.'
              : 'Running on a stored vocabulary of your own.',
          style: WaxType.body.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s12),
        Wrap(
          spacing: WaxSpace.s8,
          runSpacing: WaxSpace.s8,
          children: <Widget>[
            WaxButton(
              label: 'Preview normalization',
              kind: WaxButtonKind.tonal,
              semanticsId: SemanticsIds.genreNormalizeDryRun,
              onPressed: busy ? null : () => onNormalize(true),
            ),
            WaxButton(
              label: 'Normalize catalog',
              kind: WaxButtonKind.tonal,
              semanticsId: SemanticsIds.genreNormalize,
              onPressed: busy ? null : () => onNormalize(false),
            ),
            WaxButton(
              label: 'Revert to default',
              kind: WaxButtonKind.destructive,
              semanticsId: SemanticsIds.genreRevert,
              onPressed: busy ? null : onRevert,
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s8),
        Text(
          'A sweeper folds newly scanned genres onto the vocabulary on its '
          'own. Normalizing is the catch-up pass, for a catalog older than '
          'the change log still holds or a tree you just edited.',
          style: WaxType.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _GenreRow extends StatelessWidget {
  const _GenreRow({
    required this.node,
    required this.selected,
    required this.onTap,
  });

  final GenreNode node;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final child = node.parent != null;
    return WaxTappable(
      label: node.name,
      semanticsId: SemanticsIds.genreNode(node.name),
      selected: selected,
      borderRadius: BorderRadius.zero,
      surface: colors.canvas,
      onPressed: onTap,
      child: Material(
        color: selected ? colors.accentContainer : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(
              left: child ? WaxSpace.s32 : WaxSpace.s12,
              right: WaxSpace.s12,
              top: WaxSpace.s8,
              bottom: WaxSpace.s8,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    node.name,
                    style: (child ? WaxType.body : WaxType.titleItem).copyWith(
                      color: selected
                          ? colors.onAccentContainer
                          : colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (node.aliases.isNotEmpty)
                  Text(
                    '${node.aliases.length} alias'
                    '${node.aliases.length == 1 ? '' : 'es'}',
                    style: WaxType.caption.copyWith(color: colors.textTertiary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One genre's fields.
///
/// Every keystroke commits to the draft. It used to wait for Enter,
/// which meant typing an alias and pressing Save wrote the vocabulary
/// without it - silently, because Save was enabled by whatever edit came
/// before. Committing as you type is safe here because the draft is
/// local until Save and because the pane is keyed by the selection
/// rather than by the name, so a rename does not rebuild the field
/// underneath the caret.
class _GenreDetail extends StatefulWidget {
  const _GenreDetail({
    required this.node,
    required this.parents,
    required this.hasChildren,
    required this.isNameTaken,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });

  final GenreNode node;
  final List<String> parents;

  /// Whether anything groups under this genre. The tree is two levels
  /// deep, so a genre with children cannot itself take a parent.
  final bool hasChildren;

  /// Whether a name belongs to some other genre already. Asked before
  /// committing, so the refusal is a message on the field rather than a
  /// second node quietly sharing the name.
  final bool Function(String candidate) isNameTaken;

  final ValueChanged<GenreNode> onChanged;
  final VoidCallback onDelete;

  @override
  State<_GenreDetail> createState() => _GenreDetailState();
}

class _GenreDetailState extends State<_GenreDetail> {
  late final TextEditingController _name = TextEditingController(
    text: widget.node.name,
  );
  late final TextEditingController _aliases = TextEditingController(
    text: widget.node.aliases.join(', '),
  );

  /// Why the typed name has not been taken, when it has not.
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _aliases.dispose();
    super.dispose();
  }

  void _commitName(String raw) {
    final name = raw.trim();
    // An empty field is somebody part way through retyping, not a
    // request to erase the genre's name: nothing is committed and
    // nothing is reported until there is a name to judge.
    if (name.isEmpty || name == widget.node.name) {
      if (_nameError != null) setState(() => _nameError = null);
      return;
    }
    if (widget.isNameTaken(name)) {
      setState(() => _nameError = 'Another genre is already called $name');
      return;
    }
    if (_nameError != null) setState(() => _nameError = null);
    widget.onChanged(widget.node.copyWith(name: name));
  }

  void _commitAliases(String raw) {
    final aliases = <String>[
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    widget.onChanged(widget.node.copyWith(aliases: aliases));
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    const noParent = '(top level)';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(title: 'Genre'),
        WaxTextField(
          label: 'Name',
          controller: _name,
          errorText: _nameError,
          semanticsId: SemanticsIds.genreName,
          onChanged: _commitName,
          onSubmitted: _commitName,
        ),
        const SizedBox(height: WaxSpace.s16),
        WaxSettingRow(
          title: 'Groups under',
          help: widget.hasChildren
              ? 'Genres group under this one, and the tree is two levels deep'
              : 'The top-level genre this one belongs to',
          control: WaxChoice<String>(
            label: 'Parent genre',
            value: widget.node.parent ?? noParent,
            semanticsId: SemanticsIds.genreParent,
            options: <String>[noParent, ...widget.parents],
            labelFor: (value) => value,
            onChanged: widget.hasChildren
                ? null
                : (value) => widget.onChanged(
                    value == noParent
                        ? widget.node.copyWith(clearParent: true)
                        : widget.node.copyWith(parent: value),
                  ),
          ),
        ),
        const SizedBox(height: WaxSpace.s16),
        WaxTextField(
          label: 'Aliases',
          hint: 'Comma separated',
          controller: _aliases,
          semanticsId: SemanticsIds.genreAliases,
          onChanged: _commitAliases,
          onSubmitted: _commitAliases,
        ),
        const SizedBox(height: WaxSpace.s8),
        Text(
          'Case, accents, and punctuation already fold, so list only the '
          'spellings folding cannot reach: Rap for Hip Hop, R&B for Rhythm '
          'and Blues.',
          style: WaxType.caption.copyWith(color: colors.textTertiary),
        ),
        const SizedBox(height: WaxSpace.s16),
        WaxButton(
          label: 'Remove genre',
          kind: WaxButtonKind.destructive,
          semanticsId: SemanticsIds.genreDelete,
          onPressed: widget.onDelete,
        ),
      ],
    );
  }
}
