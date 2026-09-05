import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../providers.dart';
import '../settings/prefs_controller.dart';
import '../shell/semantics_ids.dart';
import 'radio_controller.dart';

/// Opens the add-station dialog, or the edit form for [editing].
///
/// One dialog for both because the fields are the same three and the only
/// difference is whether a directory search is offered: there is nothing to
/// search for when the station already exists.
Future<void> showAddStationDialog(
  BuildContext context, {
  RadioStation? editing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _StationDialog(editing: editing),
  );
}

/// Adds a station from a directory match. Answers null on success, or the
/// server's message when it refused.
///
/// Public because the search screen's Radio chip offers the same thing per
/// result: the directory is one surface and adding from it is one flow, so
/// the chip calls this rather than growing a second copy of it.
///
/// It returns the message rather than showing it, because where a refusal
/// belongs depends on the caller. On the search screen a snackbar is right.
/// Inside the add dialog it is not: a snackbar renders on the scaffold
/// *behind* the modal route, so the most likely refusal of all - a stream
/// URL the library already has - would have appeared under the dialog that
/// was still asking for it.
Future<String?> addDirectoryStation(
  BuildContext context,
  WidgetRef ref,
  RadioDirectoryEntry entry,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    await ref
        .read(radioStationsProvider.notifier)
        .add(
          name: entry.name,
          streamUrl: entry.streamUrl,
          homepageUrl: entry.homepageUrl,
          logoUrl: entry.logoUrl,
        );
    // The success toast is safe from the dialog too: it pops on success, so
    // the message is uncovered by the time it matters.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.radioAddedStation(entry.name))),
      );
    return null;
  } on WaxDeckApiException catch (e) {
    // The server's own words: a duplicate stream URL names the station
    // it clashes with, and the table's sentence would not.
    return explainRefusal(l10n, e);
  }
}

/// What a directory match says under its name: where it is from and what
/// it sounds like, which is how a listener picks between six results all
/// called "Jazz FM".
///
/// Public because the directory is drawn in two places, this dialog's
/// result list and search's Radio chip, and should read the same in both.
String? describeDirectoryEntry(
  AppLocalizations l10n,
  RadioDirectoryEntry entry,
) {
  final parts = <String>[
    if (entry.country != null) entry.country!,
    if (entry.bitrateKbps != null && entry.bitrateKbps! > 0)
      l10n.radioDirectoryBitrate(
        entry.codec ?? l10n.radioDirectoryStream,
        entry.bitrateKbps!,
      ),
    if (entry.tags != null && entry.tags!.isNotEmpty)
      entry.tags!.split(',').take(3).join(', '),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Opens a station's own website in the system browser.
Future<void> openStationHomepage(
  BuildContext context,
  RadioStation station,
) async {
  final homepage = station.homepageUrl;
  if (homepage == null) return;
  await ProviderScope.containerOf(
    context,
  ).read(urlOpenerProvider).open(homepage);
}

/// Mutes or unmutes one station's scrobbling, and says which it did.
///
/// Beside [openStationHomepage] because the hub's menu and the player
/// face's menu both raise it, and a toggle that reported nothing would
/// be a menu row that looks inert: the state it flips lives in a
/// preference document neither menu draws.
Future<void> toggleStationScrobble(
  BuildContext context,
  WidgetRef ref,
  RadioStation station,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final muted = await ref
        .read(prefsControllerProvider.notifier)
        .toggleRadioStationScrobble(station.pid);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            muted
                ? l10n.radioScrobbleStationMuted(station.name)
                : l10n.radioScrobbleStationResumed(station.name),
          ),
        ),
      );
    // `on Object`, not the API exception alone: the preference write
    // rethrows whatever it caught, and a serializer failure on the
    // document's round trip is not a Dio error. Both call sites here
    // fire and forget, so anything this misses is a menu that closes
    // and does nothing.
  } on Object catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(explainError(l10n, e))));
  }
}

class _StationDialog extends ConsumerStatefulWidget {
  const _StationDialog({this.editing});

  final RadioStation? editing;

  @override
  ConsumerState<_StationDialog> createState() => _StationDialogState();
}

class _StationDialogState extends ConsumerState<_StationDialog> {
  late final TextEditingController _search = TextEditingController();
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name ?? '',
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.editing?.streamUrl ?? '',
  );
  late final TextEditingController _homepage = TextEditingController(
    text: widget.editing?.homepageUrl ?? '',
  );
  late final TextEditingController _logo = TextEditingController(
    text: widget.editing?.logoUrl ?? '',
  );

  /// Editing a station has nothing to search for, so it opens on the form.
  late bool _manual = widget.editing != null;
  bool _busy = false;

  /// Whether the optional fields are showing. Open when editing, where
  /// they hold the station's existing values.
  late bool _details = _editing;

  List<RadioDirectoryEntry>? _results;

  /// The message the dialog is showing, from a search or from a save.
  String? _error;

  bool get _editing => widget.editing != null;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _url.dispose();
    _homepage.dispose();
    _logo.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final query = _search.text.trim();
    if (query.length < 2 || _busy) return;
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(repositoryProvider)
          .searchRadioDirectory(query, limit: 15);
      if (mounted) setState(() => _results = results);
    } on WaxDeckApiException catch (e) {
      if (mounted) {
        // The way out manual entry leaves open, said with the failure that
        // implies it rather than beside every message this slot shows.
        setState(
          () => _error = l10n.radioSearchFailedHint(explainError(l10n, e)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final url = _url.text.trim();
    final l10n = context.l10n;
    if (url.isEmpty) {
      setState(() => _error = l10n.radioNeedsUrl);
      return;
    }
    // The one required answer is the URL; a blank name takes the stream's
    // own host rather than blocking on a box the listener does not have
    // an answer to.
    //
    // Adding only. An edit began with the name field populated and
    // visible, so clearing it is a deliberate act, and answering it by
    // silently renaming the station after its stream host would be the
    // edit doing something nobody asked for. There is no name to fall
    // back to there, so it asks.
    final typed = _name.text.trim();
    if (_editing && typed.isEmpty) {
      setState(() {
        _error = l10n.radioNeedsName;
        _details = true;
      });
      return;
    }
    final name = typed.isEmpty ? stationNameFromUrl(url) : typed;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final editing = widget.editing;
    final homepage = _homepage.text.trim();
    final logo = _logo.text.trim();
    try {
      if (editing != null) {
        await ref
            .read(radioStationsProvider.notifier)
            .edit(
              editing.pid,
              name: name,
              streamUrl: url,
              homepageUrl: homepage.isEmpty ? null : homepage,
              logoUrl: logo.isEmpty ? null : logo,
            );
      } else {
        await ref
            .read(radioStationsProvider.notifier)
            .add(
              name: name,
              streamUrl: url,
              homepageUrl: homepage.isEmpty ? null : homepage,
              logoUrl: logo.isEmpty ? null : logo,
            );
      }
      // Only while this dialog is still up. A save outlives a dialog
      // somebody dismissed while it was in flight, and popping a
      // captured navigator then takes whatever is on top instead - the
      // screen underneath.
      if (mounted) navigator.pop();
    } on WaxDeckApiException catch (e) {
      // Inline, not a snackbar: this dialog stays open on a refusal,
      // and a snackbar would render behind it. The server's words,
      // which name the station a duplicate URL clashes with.
      if (mounted) setState(() => _error = explainRefusal(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addFromDirectory(RadioDirectoryEntry entry) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final refusal = await addDirectoryStation(context, ref, entry);
    if (refusal == null) {
      if (mounted) navigator.pop();
      return;
    }
    if (mounted) {
      setState(() {
        _error = refusal;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(_editing ? l10n.radioEditStation : l10n.radioAddStation),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Only where there is a choice: editing a station that
              // already exists has nothing to look up.
              if (!_editing)
                WaxSegmented(
                  label: l10n.radioHowToAdd,
                  segments: <WaxSegment>[
                    WaxSegment(name: 'search', label: l10n.radioAddSearch),
                    WaxSegment(name: 'url', label: l10n.radioAddByUrl),
                  ],
                  selected: _manual ? 'url' : 'search',
                  onSelect: (name) => setState(() => _manual = name == 'url'),
                ),
              const SizedBox(height: WaxSpace.s12),
              if (!_manual)
                ..._directory(l10n, colors)
              else
                ..._form(l10n, colors),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        WaxButton(
          label: l10n.commonCancel,
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (_manual)
          WaxButton(
            label: _editing ? l10n.radioSaveChanges : l10n.radioAddConfirm,
            kind: WaxButtonKind.filled,
            semanticsId: SemanticsIds.radioAddConfirm,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
      ],
    );
  }

  /// Directory search with its results.
  List<Widget> _directory(AppLocalizations l10n, WaxColors colors) => <Widget>[
    // The house search field rather than a labelled one: this asks what
    // to look for, and captioned "Station name" over a magnifier it
    // reads as the box that names the station being added - which is
    // the field further down, under the same string.
    SearchField(
      label: l10n.radioSearchDirectory,
      hint: l10n.radioStationName,
      controller: _search,
      autofocus: true,
      onSubmitted: (_) => unawaited(_runSearch()),
      semanticsId: SemanticsIds.radioSearchField,
    ),
    const SizedBox(height: WaxSpace.s8),
    WaxButton(
      label: l10n.radioSearchDirectory,
      kind: WaxButtonKind.tonal,
      icon: WaxIcons.search,
      semanticsId: SemanticsIds.radioSearchRun,
      onPressed: _busy ? null : () => unawaited(_runSearch()),
    ),
    if (_error != null)
      Padding(
        padding: const EdgeInsets.only(top: WaxSpace.s8),
        child: Text(
          _error!,
          style: WaxType.caption.copyWith(color: colors.error),
        ),
      ),
    if (_results != null)
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: _results!.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(WaxSpace.s12),
                child: Text(l10n.radioNoMatches),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _results!.length,
                itemBuilder: (context, index) {
                  final entry = _results![index];
                  return WaxOptionRow(
                    title: entry.name,
                    subtitle: describeDirectoryEntry(l10n, entry),
                    glyph: WaxIcons.radio,
                    semanticsId: SemanticsIds.radioAddDirectory(index),
                    onTap: _busy
                        ? null
                        : () => unawaited(_addFromDirectory(entry)),
                  );
                },
              ),
      ),
  ];

  /// One paste field, with everything optional behind a disclosure.
  ///
  /// What somebody has when they choose By URL is a stream address on
  /// the clipboard, and that is the only thing here they cannot supply
  /// another way: the name is derivable, and the website and logo are
  /// things the server now discovers on its own. Four boxes asked the
  /// listener to fill in three answers nobody was waiting for.
  ///
  /// The disclosure opens by default when editing, because then those
  /// fields hold a station's existing values and collapsing them would
  /// be hiding data rather than deferring a question.
  List<Widget> _form(AppLocalizations l10n, WaxColors colors) => <Widget>[
    WaxTextField(
      label: l10n.radioStreamUrl,
      controller: _url,
      hint: l10n.radioStreamUrlHint,
      autofocus: !_editing,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => unawaited(_save()),
      semanticsId: SemanticsIds.radioUrlField,
    ),
    const SizedBox(height: WaxSpace.s8),
    Align(
      alignment: Alignment.centerLeft,
      child: WaxButton(
        label: _details ? l10n.radioFewerOptions : l10n.radioMoreOptions,
        kind: WaxButtonKind.text,
        // Matching every other disclosure in the app (the audit rows, the
        // podcast folders, the queue's history): open shows the caret
        // that closes it.
        icon: _details ? WaxIcons.collapse : WaxIcons.expand,
        semanticsId: SemanticsIds.radioMoreOptions,
        onPressed: () => setState(() => _details = !_details),
      ),
    ),
    if (_details) ...<Widget>[
      const SizedBox(height: WaxSpace.s8),
      WaxTextField(
        label: l10n.radioStationName,
        controller: _name,
        hint: l10n.radioNameHint,
        semanticsId: SemanticsIds.radioNameField,
      ),
      const SizedBox(height: WaxSpace.s8),
      WaxTextField(
        label: l10n.radioWebsiteOptional,
        controller: _homepage,
        semanticsId: SemanticsIds.radioHomepageField,
      ),
      const SizedBox(height: WaxSpace.s8),
      WaxTextField(
        label: l10n.radioLogoOptional,
        controller: _logo,
        semanticsId: SemanticsIds.radioLogoField,
      ),
    ],
    if (_error != null)
      Padding(
        padding: const EdgeInsets.only(top: WaxSpace.s8),
        child: Text(
          _error!,
          style: WaxType.caption.copyWith(color: colors.error),
        ),
      ),
  ];
}

/// The name a pasted stream takes when nobody typed one: its whole host
/// minus `www.`. The last resort is untranslated on purpose - a
/// station's name is stored and read by everyone on the server.
String stationNameFromUrl(String url) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  final trimmed = host.startsWith('www.') ? host.substring(4) : host;
  return trimmed.isEmpty ? 'Station' : trimmed;
}
