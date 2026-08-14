import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/routes.dart';
import '../shell/semantics_ids.dart';
import 'playlists_controller.dart';

/// Asks for a name, a kind, and who can see it, then makes the playlist.
/// A smart choice creates nothing here: it carries the answers into the
/// rule editor, because a smart list without a rule matches everything.
Future<void> showCreatePlaylistDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _CreatePlaylistDialog(),
);

/// Asks for a playlist name and nothing else. Pops with the trimmed
/// name, or null on cancel. Its own controller: one built inline in an
/// async handler cannot be safely disposed.
Future<String?> promptPlaylistName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NamePromptDialog(
    title: title,
    confirmLabel: confirmLabel,
    initial: initial,
  ),
);

class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.confirmLabel,
    required this.initial,
  });

  final String title;
  final String confirmLabel;
  final String initial;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: WaxTextField(
        label: context.l10n.playlistNameLabel,
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _confirm(),
        semanticsId: SemanticsIds.playlistNameField,
      ),
    ),
    actions: <Widget>[
      WaxButton(
        label: context.l10n.commonCancel,
        kind: WaxButtonKind.text,
        onPressed: () => Navigator.of(context).pop(),
      ),
      WaxButton(
        label: widget.confirmLabel,
        semanticsId: SemanticsIds.playlistCreateConfirm,
        onPressed: _confirm,
      ),
    ],
  );
}

class _CreatePlaylistDialog extends ConsumerStatefulWidget {
  const _CreatePlaylistDialog();

  @override
  ConsumerState<_CreatePlaylistDialog> createState() =>
      _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends ConsumerState<_CreatePlaylistDialog> {
  final _name = TextEditingController();
  var _kind = 'static';
  var _shared = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    final name = _name.text.trim();
    final l10n = context.l10n;
    if (name.isEmpty) {
      setState(() => _error = l10n.playlistNameRequired);
      return;
    }
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    if (_kind == 'smart') {
      navigator.pop();
      await router.push<void>(
        WaxRoute.playlistRules,
        extra: RuleDraftArgs(name: name, shared: _shared),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(playlistsProvider.notifier)
          .create(
            name: name,
            kind: 'static',
            visibility: _shared ? 'shared' : null,
          );
      // Nothing if the dialog was dismissed mid-request: popping would
      // take the screen underneath. The list exists either way.
      if (!mounted) return;
      navigator.pop();
      router.go(WaxRoute.playlist(created.pid));
    } on WaxDeckApiException catch (e) {
      // The server's own words: a name it refused is a value somebody
      // just typed, and only it knows what was wrong with it.
      if (mounted) setState(() => _error = explainRefusal(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.playlistsNew),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WaxTextField(
              label: l10n.playlistNameLabel,
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => unawaited(_create()),
              semanticsId: SemanticsIds.playlistNameField,
            ),
            const SizedBox(height: WaxSpace.s12),
            FilterChipRow(
              padding: EdgeInsets.zero,
              selected: _kind,
              chips: <WaxFilterChip>[
                WaxFilterChip(
                  name: 'static',
                  label: l10n.playlistKindManual,
                  semanticsId: SemanticsIds.playlistCreateKind('static'),
                ),
                WaxFilterChip(
                  name: 'smart',
                  label: l10n.playlistSmart,
                  semanticsId: SemanticsIds.playlistCreateKind('smart'),
                ),
              ],
              onSelect: (kind) => setState(() => _kind = kind),
            ),
            const SizedBox(height: WaxSpace.s4),
            Text(
              _kind == 'smart'
                  ? l10n.playlistKindSmartHelp
                  : l10n.playlistKindManualHelp,
              style: WaxType.caption.copyWith(color: colors.textTertiary),
            ),
            WaxSettingRow(
              key: const Key(SemanticsIds.playlistCreateShared),
              title: l10n.playlistSharedWithEveryone,
              help: l10n.playlistSharedHelp,
              control: WaxSwitch(
                value: _shared,
                label: l10n.playlistSharedWithEveryone,
                semanticsId: SemanticsIds.playlistCreateShared,
                onChanged: (v) => setState(() => _shared = v),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: WaxType.caption.copyWith(color: colors.error),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WaxButton(
          label: _kind == 'smart'
              ? l10n.playlistCreateNext
              : l10n.playlistCreateAction,
          semanticsId: SemanticsIds.playlistCreateConfirm,
          onPressed: _busy ? null : () => unawaited(_create()),
        ),
      ],
    );
  }
}
