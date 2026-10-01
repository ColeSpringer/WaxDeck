import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../shell/semantics_ids.dart';
import '../shell/shell_messages.dart';
import 'organize_screen.dart';

/// How long typing rests before the samples are asked for again.
const _sampleDebounce = Duration(milliseconds: 300);

/// Edits an organize profile, or makes one when [profile] is null: its
/// templates, tag writing, and where they lay out the sample items.
Future<void> showOrganizeProfileEditor(
  BuildContext context, {
  OrganizeProfile? profile,
}) => showWaxSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ProfileEditorSheet(profile: profile),
);

class _ProfileEditorSheet extends ConsumerStatefulWidget {
  const _ProfileEditorSheet({required this.profile});

  final OrganizeProfile? profile;

  @override
  ConsumerState<_ProfileEditorSheet> createState() =>
      _ProfileEditorSheetState();
}

class _ProfileEditorSheetState extends ConsumerState<_ProfileEditorSheet> {
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  // What the profile sets itself; an empty field inherits, its hint says what.
  late final _music = TextEditingController(
    text: widget.profile?.saved?.music ?? '',
  );
  late final _audiobook = TextEditingController(
    text: widget.profile?.saved?.audiobook ?? '',
  );
  late final _podcast = TextEditingController(
    text: widget.profile?.saved?.podcast ?? '',
  );
  late var _tagWrite = widget.profile?.tagWrite ?? false;
  late OrganizeSample? _sample = widget.profile?.sample;
  String? _sampleError;

  /// A refused save or delete: the shell's toast would sit under the sheet.
  String? _refusal;
  Timer? _debounce;

  /// Numbers the sample requests, so only the newest answer lands.
  var _sampleRequest = 0;
  var _busy = false;

  bool get _editing => widget.profile != null;

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _music.dispose();
    _audiobook.dispose();
    _podcast.dispose();
    super.dispose();
  }

  void _templatesChanged() {
    _debounce?.cancel();
    _debounce = Timer(_sampleDebounce, () => unawaited(_renderSamples()));
  }

  Future<void> _renderSamples() async {
    final l10n = context.l10n;
    final request = ++_sampleRequest;
    try {
      final sample = await ref
          .read(repositoryProvider)
          .previewOrganizeProfile(
            name: _name.text.trim(),
            musicTemplate: _music.text,
            audiobookTemplate: _audiobook.text,
            podcastTemplate: _podcast.text,
          );
      if (mounted && request == _sampleRequest) {
        setState(() {
          _sample = sample;
          _sampleError = null;
        });
      }
    } on WaxDeckApiException catch (error) {
      // The template is what somebody just typed: the server's sentence
      // names what is wrong with it.
      if (mounted && request == _sampleRequest) {
        setState(() => _sampleError = explainRefusal(l10n, error));
      }
    }
  }

  /// Shows a refusal in the sheet, or, the sheet gone, as a toast.
  void _refused(ShellMessenger messenger, String message) {
    if (mounted) {
      setState(() => _refusal = message);
    } else {
      messenger.show(message);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final l10n = context.l10n;
    // The sheet can be dismissed before the answer; the container outlives it.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = container.read(shellMessengerProvider.notifier);
    setState(() {
      _busy = true;
      _refusal = null;
    });
    try {
      await container
          .read(repositoryProvider)
          .putOrganizeProfile(
            name,
            musicTemplate: _music.text,
            audiobookTemplate: _audiobook.text,
            podcastTemplate: _podcast.text,
            tagWrite: _tagWrite,
          );
      container.invalidate(organizeProfilesProvider);
      messenger.show(l10n.organizeProfileSaved(name));
      if (mounted) Navigator.of(context).pop();
    } on WaxDeckApiException catch (error) {
      _refused(messenger, explainRefusal(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String name) async {
    final l10n = context.l10n;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = container.read(shellMessengerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.organizeProfileDeleteTitle(name)),
        content: WaxProse(l10n.organizeProfileDeleteBody),
        actions: <Widget>[
          WaxButton(
            label: l10n.commonCancel,
            kind: WaxButtonKind.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          WaxButton(
            label: l10n.organizeProfileDelete,
            kind: WaxButtonKind.destructive,
            semanticsId: SemanticsIds.organizeProfileDeleteConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _refusal = null;
    });
    try {
      await container.read(repositoryProvider).deleteOrganizeProfile(name);
      container.invalidate(organizeProfilesProvider);
      messenger.show(l10n.organizeProfileDeleted(name));
      if (mounted) Navigator.of(context).pop();
    } on WaxDeckApiException catch (error) {
      // A library still laid out by it: the server names which.
      _refused(messenger, explainRefusal(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final profile = widget.profile;
    final sample = _sample;
    final typed = _name.text.trim();
    final taken =
        !_editing &&
        (ref.watch(organizeProfilesProvider).value?.profiles ?? const []).any(
          (p) => p.name == typed,
        );
    Widget template(
      String label,
      TextEditingController controller,
      String semanticsId,
      String inherited,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s12),
      child: WaxTextField(
        label: label,
        hint: inherited.isEmpty ? l10n.organizeProfileTemplateHint : inherited,
        controller: controller,
        semanticsId: semanticsId,
        onChanged: (_) => _templatesChanged(),
      ),
    );
    // A field the profile leaves empty inherits what the listing shows.
    String inherited(String? saved, String? effective) =>
        (saved ?? '').isEmpty ? effective ?? '' : '';
    String line(String path) =>
        path.isEmpty ? l10n.organizeProfileSampleNone : path;
    return SafeArea(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        identifier: SemanticsIds.organizeProfileSheet,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: WaxSpace.s16,
            right: WaxSpace.s16,
            top: WaxSpace.s16,
            bottom: WaxSpace.s16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                profile == null
                    ? l10n.organizeProfileNew
                    : l10n.organizeProfileEditTitle(profile.name),
                style: WaxType.headline.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: WaxSpace.s12),
              if (!_editing)
                Padding(
                  padding: const EdgeInsets.only(bottom: WaxSpace.s12),
                  child: WaxTextField(
                    label: l10n.organizeProfileNameLabel,
                    controller: _name,
                    autofocus: true,
                    semanticsId: SemanticsIds.organizeProfileName,
                    errorText: taken
                        ? l10n.organizeProfileNameTaken(typed)
                        : null,
                    // The name picks what empty templates inherit.
                    onChanged: (_) {
                      setState(() {});
                      _templatesChanged();
                    },
                  ),
                ),
              template(
                l10n.organizeProfileMusicLabel,
                _music,
                SemanticsIds.organizeProfileMusic,
                inherited(profile?.saved?.music, profile?.musicTemplate),
              ),
              template(
                l10n.organizeProfileAudiobookLabel,
                _audiobook,
                SemanticsIds.organizeProfileAudiobook,
                inherited(
                  profile?.saved?.audiobook,
                  profile?.audiobookTemplate,
                ),
              ),
              template(
                l10n.organizeProfilePodcastLabel,
                _podcast,
                SemanticsIds.organizeProfilePodcast,
                inherited(profile?.saved?.podcast, profile?.podcastTemplate),
              ),
              WaxSettingRow(
                title: l10n.organizeProfileTagWrite,
                help: l10n.organizeProfileTagWriteHelp,
                control: WaxSwitch(
                  label: l10n.organizeProfileTagWrite,
                  value: _tagWrite,
                  semanticsId: SemanticsIds.organizeProfileTagWrite,
                  onChanged: (on) => setState(() => _tagWrite = on),
                ),
              ),
              const SizedBox(height: WaxSpace.s12),
              Semantics(
                container: true,
                identifier: SemanticsIds.organizeProfileSample,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      l10n.organizeProfileSampleTitle,
                      style: WaxType.overline.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: WaxSpace.s4),
                    if (_sampleError case final error?)
                      Text(
                        error,
                        style: WaxType.bodySmall.copyWith(color: colors.error),
                      )
                    else if (sample != null)
                      for (final text in <String>[
                        l10n.organizeProfileSampleMusic(line(sample.music)),
                        l10n.organizeProfileSampleBook(line(sample.audiobook)),
                        l10n.organizeProfileSamplePodcast(line(sample.podcast)),
                      ])
                        Text(
                          text,
                          style: WaxType.monoData.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: WaxSpace.s16),
              if (_refusal case final refusal?)
                Padding(
                  padding: const EdgeInsets.only(bottom: WaxSpace.s12),
                  child: Text(
                    refusal,
                    style: WaxType.bodySmall.copyWith(color: colors.error),
                  ),
                ),
              Row(
                children: <Widget>[
                  if (profile != null && !profile.builtIn)
                    WaxButton(
                      label: l10n.organizeProfileDelete,
                      kind: WaxButtonKind.text,
                      semanticsId: SemanticsIds.organizeProfileDelete(
                        profile.name,
                      ),
                      onPressed: _busy ? null : () => _delete(profile.name),
                    ),
                  const Spacer(),
                  WaxButton(
                    label: l10n.organizeProfileSave,
                    semanticsId: SemanticsIds.organizeProfileSave,
                    busy: _busy,
                    onPressed: _busy || typed.isEmpty || taken
                        ? null
                        : () => unawaited(_save()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
