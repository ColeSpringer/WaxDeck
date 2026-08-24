import 'package:desktop_drop/desktop_drop.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../shell/semantics_ids.dart';
import 'file_picker_impl.dart' as impl;
import 'file_picker_port.dart';

/// Flattens a drop into lazy picked-file references, filtered to
/// [extensions], with what the filter dropped counted the way a folder
/// pick counts it. Two shapes arrive today - recursive children (web)
/// and a plain path (Linux, Windows) - and a childless directory item
/// is kept as the defensive third.
Future<FolderPick> normalizeDrop(
  List<DropItem> items,
  Set<String> extensions,
) async {
  final out = <PickedAudioFile>[];
  var skippedUnsupported = 0;
  var skippedDrm = 0;
  void count(String name) =>
      hasRejectedExtension(name) ? skippedDrm++ : skippedUnsupported++;
  void merge(FolderPick expanded) {
    out.addAll(expanded.files);
    skippedUnsupported += expanded.skippedUnsupported;
    skippedDrm += expanded.skippedDrm;
  }

  Future<void> walk(DropItem item, String parentDir) async {
    if (item is DropItemDirectory) {
      if (item.children.isNotEmpty) {
        final dir = parentDir.isEmpty ? item.name : '$parentDir/${item.name}';
        for (final child in item.children) {
          await walk(child, dir);
        }
        return;
      }
      merge(await impl.expandDroppedDirectory(item.path, extensions));
      return;
    }
    if (await impl.droppedPathIsDirectory(item.path)) {
      merge(await impl.expandDroppedDirectory(item.path, extensions));
      return;
    }
    if (!hasAcceptedExtension(item.name, extensions)) {
      count(item.name);
      return;
    }
    out.add(await impl.pickedFromXFile(item, relativeDir: parentDir));
  }

  for (final item in items) {
    await walk(item, '');
  }
  return FolderPick(
    files: out,
    skippedUnsupported: skippedUnsupported,
    skippedDrm: skippedDrm,
  );
}

/// A drop zone for audio, or with another extension set for archives and
/// cover images. The only file that touches desktop_drop.
class AudioDropArea extends StatefulWidget {
  const AudioDropArea({
    super.key,
    required this.child,
    required this.onDropped,
    required this.hint,
    this.onSkipped,
    this.enabled = true,
    this.extensions = kAcceptedAudioExtensions,
    this.semanticsId = SemanticsIds.uploadDropTarget,
  });

  final Widget child;
  final Future<void> Function(List<PickedAudioFile> files) onDropped;

  /// What the drop's extension filter left behind, for the audio zones
  /// that report it (an Audible folder dragged onto home used to vanish
  /// without a word). Called before [onDropped], and also when nothing
  /// survived at all - the case [onDropped] never hears about. The
  /// zones taking images or archives pass nothing and stay quiet.
  final void Function({
    required int unsupported,
    required int drm,
    required bool nothingKept,
  })?
  onSkipped;

  /// Gated off for callers without upload rights; a disabled area is
  /// just its child.
  final bool enabled;

  final Set<String> extensions;

  /// Overlay caption while hovering, and the zone's spoken name.
  /// Required, because a defaulted sentence is one language every
  /// caller who forgets it draws in all of them.
  final String hint;

  /// The zone's own handle. Defaulted to the uploads target, which is
  /// what a page-sized drop zone is; a screen with several zones on it
  /// (the artwork slots) names each one.
  final String semanticsId;

  @override
  State<AudioDropArea> createState() => _AudioDropAreaState();
}

class _AudioDropAreaState extends State<AudioDropArea> {
  var _hovering = false;

  Future<void> _dropped(DropDoneDetails details) async {
    setState(() => _hovering = false);
    final drop = await normalizeDrop(details.files, widget.extensions);
    if (!mounted) return;
    if (drop.skippedUnsupported + drop.skippedDrm > 0) {
      widget.onSkipped?.call(
        unsupported: drop.skippedUnsupported,
        drm: drop.skippedDrm,
        nothingKept: drop.files.isEmpty,
      );
    }
    if (drop.files.isEmpty) return;
    await widget.onDropped(drop.files);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return DropTarget(
      // Not while something is pushed over it: a screen underneath keeps
      // its bounds, so a page-wide zone would accept a drop aimed at the
      // editor on top of it.
      enable: widget.enabled && (ModalRoute.of(context)?.isCurrent ?? true),
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: _dropped,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          widget.child,
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: Semantics(
                  identifier: widget.semanticsId,
                  label: widget.hint,
                  container: true,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.08),
                      border: Border.all(color: colors.accent, width: 2),
                      borderRadius: WaxRadius.card,
                    ),
                    alignment: Alignment.center,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.accentContainer,
                        borderRadius: WaxRadius.chip,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: WaxSpace.s16,
                          vertical: WaxSpace.s12,
                        ),
                        child: Text(
                          widget.hint,
                          textAlign: TextAlign.center,
                          style: WaxType.label.copyWith(
                            color: colors.onAccentContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
