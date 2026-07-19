import 'package:flutter/material.dart';

/// A single-field playlist-name prompt that owns its text controller.
/// Dialogs built inline in async handlers leak theirs: nothing can
/// safely dispose a controller the closing route's field is still
/// detaching from. Pops with the trimmed name, or null on cancel.
class NamePromptDialog extends StatefulWidget {
  const NamePromptDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.fieldKey,
    required this.confirmKey,
    this.initial = '',
  });

  final String title;
  final String confirmLabel;
  final Key fieldKey;
  final Key confirmKey;
  final String initial;

  @override
  State<NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<NamePromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: widget.fieldKey,
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Playlist name'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: widget.confirmKey,
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
