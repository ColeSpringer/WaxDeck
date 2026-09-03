import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/shell_messages.dart';
import 'metadata_form.dart';

/// The copy one rename section draws.
///
/// Stated by the caller rather than derived from the entity type: what
/// the section is renaming is the same operation every time, but the
/// sentence that explains it is not - a release's members are its
/// tracks, an artist's are every track crediting them, and a release
/// group's are whole albums.
class RenameSectionCopy {
  const RenameSectionCopy({
    required this.title,
    required this.overline,
    required this.help,
    required this.applyLabel,
    required this.confirmTitle,
    required this.confirmBody,
    required this.merged,
    required this.renamed,
  });

  final String title;
  final String overline;
  final String help;

  /// The button, and the confirmation's own confirm button with it.
  final String applyLabel;

  final String confirmTitle;
  final String confirmBody;

  /// Shown when a taken name folded this entity into an incumbent and
  /// the caller is about to follow it.
  final String merged;

  /// Shown when the entity kept its row, given the member count the
  /// rename carried.
  final String Function(int members) renamed;
}

/// The semantics identifiers one rename section hangs on its controls.
///
/// Per caller and not derived, because they are a contract: the e2e
/// suite imports these same constants, so the album pane's `albumRewrite*`
/// names have to survive being served by shared code.
class RenameSectionIds {
  const RenameSectionIds({
    required this.field,
    required this.writeBack,
    required this.apply,
    required this.confirm,
    this.section,
  });

  final String Function(String field) field;
  final String writeBack;
  final String apply;
  final String confirm;

  /// Wraps the whole section when the caller's surface needs to address
  /// it as one node; null leaves the rows in their parent's tree.
  final String? section;
}

/// The keying fields of an entity, edited together and applied through
/// the rename verb.
///
/// One component for both surfaces that offer this - the release
/// workbench's album pane and the artist/release-group editor - because
/// what they do is identical and only the copy differs. Two copies of
/// it drifted immediately: the merge branch, the deliberate `force`,
/// the write-back warning and the "did the row survive" question are
/// all subtle enough that a later fix would land on one and be missed
/// on the other.
///
/// It owns the inputs and the write; the caller owns the seed (the two
/// read different things to find the current values), where a merge
/// takes the surface, and what to refetch when the row survives.
class EntityRenameSection extends ConsumerStatefulWidget {
  const EntityRenameSection({
    super.key,
    required this.entityType,
    required this.pid,
    required this.fields,
    required this.seed,
    required this.onRetrySeed,
    required this.copy,
    required this.ids,
    required this.busy,
    required this.onBusyChanged,
    required this.onMerged,
    required this.onRenamed,
    this.canApply = true,
    this.onDirtyChanged,
  });

  /// The wire entity type the rename endpoint takes.
  final String entityType;
  final String pid;

  /// The keying fields this rung owns, in the order they are drawn.
  final List<String> fields;

  /// The values the inputs start from, keyed by field. The caller reads
  /// them: an album pane has a member's metadata in hand, and the
  /// entity editor deliberately seeds an artist empty.
  final AsyncValue<Map<String, String>> seed;
  final VoidCallback onRetrySeed;

  final RenameSectionCopy copy;
  final RenameSectionIds ids;

  /// The host's busy flag, so its other forms disable together with
  /// this one rather than each holding a flag of its own.
  final bool busy;
  final ValueChanged<bool> onBusyChanged;

  /// Where the surface goes when a taken name merged this entity away:
  /// the survivor's pid. The caller owns the move because a pane in a
  /// sheet has a sheet to close and a screen has a route to replace.
  final ValueChanged<String> onMerged;

  /// Called when the row survived, for whatever the caller has to
  /// refetch.
  final VoidCallback onRenamed;

  /// Extra precondition on the apply button, for a caller that knows
  /// one: the album pane refuses a release it counts no members on.
  final bool canApply;

  /// Reports whether the inputs hold anything unsaved, for a host that
  /// tracks dirtiness across several forms.
  final ValueChanged<bool>? onDirtyChanged;

  @override
  ConsumerState<EntityRenameSection> createState() =>
      _EntityRenameSectionState();
}

class _EntityRenameSectionState extends ConsumerState<EntityRenameSection> {
  final _controllers = <String, TextEditingController>{};

  /// What each controller was last seeded with, which is what a staged
  /// value is diffed against.
  final _seeded = <String, String>{};

  var _writeBack = false;
  var _reportedDirty = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String field, String initial) =>
      _controllers.putIfAbsent(field, () {
        _seeded[field] = initial;
        final controller = TextEditingController(text: initial);
        controller.addListener(() {
          setState(() {});
          _reportDirty();
        });
        return controller;
      });

  /// Only the fields that differ from what the members carry.
  Map<String, String> _staged() {
    final staged = <String, String>{};
    for (final field in widget.fields) {
      final controller = _controllers[field];
      if (controller == null) continue;
      if (controller.text != _seeded[field]) {
        staged[field] = controller.text;
      }
    }
    return staged;
  }

  void _reportDirty() {
    final onDirty = widget.onDirtyChanged;
    if (onDirty == null) return;
    final dirty = _staged().isNotEmpty;
    if (dirty != _reportedDirty) {
      _reportedDirty = dirty;
      onDirty(dirty);
    }
  }

  /// What one keying field is called. A property of the field rather
  /// than of the caller: `name` is the artist rung's own, and the rest
  /// are item fields the editor vocabulary already names.
  String _labelOf(AppLocalizations l10n, String field) => field == 'name'
      ? l10n.musicFieldArtistName
      : metadataFieldLabel(l10n, field);

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final staged = _staged();
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(title: widget.copy.title, overline: widget.copy.overline),
        Text(
          widget.copy.help,
          style: WaxType.bodySmall.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: WaxSpace.s12),
        // Rows only from a resolved seed. The controllers seed on first
        // sight, so building them from an error would leave them empty
        // for good and a named entity would read blank until the
        // surface was remounted.
        ...switch (widget.seed) {
          AsyncValue(value: final seeds?) => <Widget>[
            for (final field in widget.fields) ...<Widget>[
              WaxTextField(
                label: _labelOf(l10n, field),
                controller: _controllerFor(field, seeds[field] ?? ''),
                digitsOnly: field == 'year',
                semanticsId: widget.ids.field(field),
              ),
              const SizedBox(height: WaxSpace.s12),
            ],
            WaxSettingRow(
              title: l10n.metadataWriteBackTitle,
              help: l10n.musicEntityRenameWriteBackHelp,
              control: WaxSwitch(
                label: l10n.metadataWriteBackTitle,
                value: _writeBack,
                semanticsId: widget.ids.writeBack,
                onChanged: (v) => setState(() => _writeBack = v),
              ),
            ),
            const SizedBox(height: WaxSpace.s8),
            WaxButton(
              label: widget.copy.applyLabel,
              icon: WaxIcons.edit,
              kind: WaxButtonKind.tonal,
              semanticsId: widget.ids.apply,
              onPressed: staged.isEmpty || widget.busy || !widget.canApply
                  ? null
                  : () => _apply(staged),
            ),
          ],
          AsyncValue(hasError: true, error: final Object error) => <Widget>[
            ErrorState(
              title: l10n.metadataLoadError,
              message: context.explain(error),
              onRetry: widget.onRetrySeed,
            ),
          ],
          _ => const <Widget>[SkeletonShapes(shape: SkeletonShape.list)],
        },
      ],
    );
    final id = widget.ids.section;
    if (id == null) return body;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: id,
      child: body,
    );
  }

  Future<void> _apply(Map<String, String> staged) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.copy.confirmTitle),
        content: Text(widget.copy.confirmBody),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: widget.copy.applyLabel,
            semanticsId: widget.ids.confirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false) || !mounted || widget.busy) return;
    widget.onBusyChanged(true);
    final messenger = ref.read(shellMessengerProvider.notifier);
    try {
      // The rename enumerates the members server-side, which is the
      // point: a client-drained list that stopped short would move the
      // ones it had and strand the rest, splitting the entity.
      //
      // Force, deliberately: the rename locks these fields on every
      // member, so a second one would otherwise refuse on the locks the
      // first took.
      final result = await ref
          .read(repositoryProvider)
          .renameEntity(
            widget.entityType,
            widget.pid,
            fields: staged,
            writeBack: _writeBack,
            force: true,
          );
      // The write may land while the surface is being left - a merge
      // moves it, and a sheet can be closed under it. Reading through a
      // disposed ref throws past the catch, which only knows the
      // server's refusals.
      if (!mounted) return;
      for (final entry in staged.entries) {
        _seeded[entry.key] = entry.value;
      }
      _reportDirty();
      final merged = result.outcome == EntityRenameOutcome.merged;
      messenger.show(
        <String>[
          merged ? widget.copy.merged : widget.copy.renamed(result.members),
          if (result.writeBackFailures.isNotEmpty)
            l10n.metadataWriteBackWarning,
        ].join('\n'),
      );
      if (merged && result.mergedInto != null) {
        widget.onMerged(result.mergedInto!);
        return;
      }
      widget.onRenamed();
    } on WaxDeckApiException catch (e) {
      if (mounted) messenger.show(explainRefusal(l10n, e));
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }
}
