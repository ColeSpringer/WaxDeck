import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../shell/semantics_ids.dart';
import 'file_picker_impl.dart' as impl;
import 'file_picker_port.dart';

/// Flattens a drop payload into lazy picked-file references, filtered
/// to [extensions]. Handles the three shapes drops arrive in: web
/// directory items carry their children recursively (relative
/// directories rebuild from the nesting), Linux and Windows deliver a
/// dropped folder as a plain path item (expanded on disk), and macOS
/// marks it a directory item with no children (same expansion).
Future<List<PickedAudioFile>> normalizeDrop(
  List<DropItem> items,
  Set<String> extensions,
) async {
  final out = <PickedAudioFile>[];
  Future<void> walk(DropItem item, String parentDir) async {
    if (item is DropItemDirectory) {
      if (item.children.isNotEmpty) {
        final dir = parentDir.isEmpty ? item.name : '$parentDir/${item.name}';
        for (final child in item.children) {
          await walk(child, dir);
        }
        return;
      }
      out.addAll(await impl.expandDroppedDirectory(item.path, extensions));
      return;
    }
    if (await impl.droppedPathIsDirectory(item.path)) {
      out.addAll(await impl.expandDroppedDirectory(item.path, extensions));
      return;
    }
    if (!hasAcceptedExtension(item.name, extensions)) return;
    out.add(await impl.pickedFromXFile(item, relativeDir: parentDir));
  }

  for (final item in items) {
    await walk(item, '');
  }
  return out;
}

/// A drag-and-drop landing zone for audio (or, with a different
/// extension set, backup archives): wraps [child], shows a hover
/// overlay while a drag is over the window, and hands the normalized
/// files to [onDropped]. The only file that touches desktop_drop.
class AudioDropArea extends StatefulWidget {
  const AudioDropArea({
    super.key,
    required this.child,
    required this.onDropped,
    this.enabled = true,
    this.extensions = kAcceptedAudioExtensions,
    this.hint = 'Drop audio files to upload',
  });

  final Widget child;
  final Future<void> Function(List<PickedAudioFile> files) onDropped;

  /// Gated off for callers without upload rights; a disabled area is
  /// just its child.
  final bool enabled;

  final Set<String> extensions;

  /// Overlay caption while hovering.
  final String hint;

  @override
  State<AudioDropArea> createState() => _AudioDropAreaState();
}

class _AudioDropAreaState extends State<AudioDropArea> {
  var _hovering = false;

  Future<void> _dropped(DropDoneDetails details) async {
    setState(() => _hovering = false);
    final files = await normalizeDrop(details.files, widget.extensions);
    if (files.isEmpty || !mounted) return;
    await widget.onDropped(files);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: _dropped,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: Semantics(
                  identifier: SemanticsIds.uploadDropTarget,
                  label: widget.hint,
                  child: Container(
                    key: const Key(SemanticsIds.uploadDropTarget),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      border: Border.all(color: colorScheme.primary, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Text(
                          widget.hint,
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
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
