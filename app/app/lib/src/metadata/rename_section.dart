import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../music/music_controllers.dart';
import '../providers.dart';
import '../shell/async_box_face.dart';
import '../shell/navigation_history.dart';
import '../shell/routes.dart';
import '../shell/shell_messages.dart';
import 'metadata_form.dart';

/// Where an edit's answer takes the page whose record it edited. Read from
/// that page while it is mounted, before the server is asked, so the
/// follow is the same once the pane, sheet or page that asked has gone.
/// [pid] is the record's; [closing], a sheet that asked, closes as the
/// follow is made. What it says is worded where it is drawn, in the
/// locale then.
class EditFollow {
  EditFollow.of(BuildContext context, {required this.pid, this.closing})
    : _router = GoRouter.of(context),
      _from = pageIn(context),
      _messenger = ShellMessenger.of(context);

  final String pid;
  final Route<Object?>? closing;
  final GoRouter _router;
  final PageId _from;
  final ShellMessenger _messenger;

  /// The record was merged into [survivor]. While the visitor is on the
  /// page that asked or on another of the record's (any visit of its
  /// editor, its album, artist or release group page), the survivor's
  /// takes its place, saying [said]; otherwise one message offers the
  /// survivor where they are. Either way no page of the record is shown
  /// again: taken out from under the page on top, and every visit of it
  /// forgotten. [also] goes under either message.
  Future<void> merged(
    String survivor, {
    required String Function(AppLocalizations l10n) said,
    List<String Function(AppLocalizations l10n)> also = const [],
  }) async {
    final to = WaxRoute.metadata(survivor);
    final pages = _pagesOf(pid, survivor);
    String? instead(String location) {
      for (final (gone, kept) in pages) {
        if (location == gone || location.startsWith('$gone/')) {
          return kept + location.substring(gone.length);
        }
      }
      return null;
    }

    String lines(AppLocalizations l10n, String first) =>
        <String>[first, for (final line in also) line(l10n)].join('\n');
    closeFinished(closing);
    String? swapTo;
    final on = await stillOnTop(_router, (page) {
      swapTo = page == _from ? to : instead(page.location);
      return swapTo != null;
    });
    if (on) {
      _messenger.showLocalized((l10n) => lines(l10n, said(l10n)));
      _swap(swapTo!);
    }
    final history = WaxHistory.of(_router);
    history?.takeOutFromUnder(
      (location, _) => instead(Uri.parse(location).path) != null,
      instead: instead,
    );
    for (final (gone, kept) in pages) {
      history?.forget(gone, instead: kept);
    }
    if (on) return;
    _messenger.showLocalized(
      (l10n) => lines(l10n, l10n.metadataMergedReady),
      actionLabelOf: (l10n) => l10n.commonOpen,
      onAction: () => unawaited(_router.pushInShell<void>(to)),
    );
  }

  /// The pages of [gone], each with the page of [survivor] it stands for:
  /// its editor, and for an album, artist or release group its own page.
  static List<(String, String)> _pagesOf(String gone, String survivor) => [
    (WaxRoute.metadata(gone), WaxRoute.metadata(survivor)),
    for (final dimension in MusicDimension.values)
      if (dimension.entityPrefix case final prefix?
          when gone.startsWith(prefix))
        (
          WaxRoute.musicBucket(dimension, gone),
          WaxRoute.musicBucket(dimension, survivor),
        ),
  ];

  /// Opens [location], as the visitor asked: in place of the page while
  /// they are still on it, else where they are.
  Future<void> open(String location) async {
    closeFinished(closing);
    if (await stillOnTop(_router, (page) => page == _from)) {
      _swap(location);
    } else {
      unawaited(_router.pushInShell<void>(location));
    }
  }

  /// [WaxBack.swap] from under the router, as the page may have gone.
  void _swap(String location) =>
      _router.routerDelegate.navigatorKey.currentContext?.swap(location);
}

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
    required this.help,
    required this.applyLabel,
    required this.confirmTitle,
    required this.confirmBody,
    required this.merged,
    required this.renamed,
  });

  final String title;
  final String help;

  /// The button, and the confirmation's own confirm button with it.
  final String applyLabel;

  final String confirmTitle;
  final String confirmBody;

  /// Shown when a taken name folded this entity into an incumbent and
  /// the caller is about to follow it, worded where it is drawn.
  final String Function(AppLocalizations l10n) merged;

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
    required this.follow,
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

  /// Where the surface goes when a taken name merged this entity away,
  /// read as the rename is sent; none where the page it was opened from has
  /// gone, and then the merge is only said. The caller owns the move
  /// because a pane in a sheet has a sheet to close and a screen has a
  /// route to replace.
  final EditFollow? Function() follow;

  /// Called when the row survived, for whatever the caller has to
  /// refetch, whether or not this section is still up.
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
        SectionHeader(title: widget.copy.title),
        WaxProse(
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
                semanticsId: widget.ids.field(field),
              ),
              const SizedBox(height: WaxSpace.s12),
            ],
            WaxSettingRow(
              title: l10n.metadataWriteBackTitle,
              // The widest write on the screen: every member's file.
              info: l10n.musicEntityRenameWriteBackHelp,
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
          AsyncValue(hasError: true) => <Widget>[
            AsyncFailureCard.from(
              widget.seed,
              title: l10n.metadataLoadError,
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
        content: WaxProse(widget.copy.confirmBody),
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
    final messenger = ref.read(shellMessengerProvider);
    final copy = widget.copy;
    final onRenamed = widget.onRenamed;
    final follow = widget.follow();
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
      final merged = result.outcome == EntityRenameOutcome.merged;
      final warning = <String Function(AppLocalizations l10n)>[
        if (result.writeBackFailures.isNotEmpty)
          (l10n) => l10n.metadataWriteBackWarning,
      ];
      String said(String first) =>
          <String>[first, for (final line in warning) line(l10n)].join('\n');
      // The write may land while the surface is being left - a merge
      // moves it, and a sheet can be closed under it. Reading through a
      // disposed ref throws past the catch, which only knows the
      // server's refusals.
      if (mounted) {
        for (final entry in staged.entries) {
          _seeded[entry.key] = entry.value;
        }
        _reportDirty();
      }
      // Followed whether or not this section is still up: what it renamed
      // is gone.
      if (result.mergedInto case final survivor? when merged) {
        if (follow != null) {
          unawaited(follow.merged(survivor, said: copy.merged, also: warning));
        } else {
          messenger.show(said(copy.merged(l10n)));
        }
        return;
      }
      // Said where the visitor is, this section up or not.
      messenger.show(
        said(merged ? copy.merged(l10n) : copy.renamed(result.members)),
      );
      onRenamed();
    } on WaxDeckApiException catch (e) {
      messenger.show(explainRefusal(l10n, e));
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }
}
