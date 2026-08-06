import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../providers.dart';
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
      ..showSnackBar(SnackBar(content: Text('Added ${entry.name}')));
    return null;
  } on WaxDeckApiException catch (e) {
    return e.message;
  }
}

/// What a directory match says under its name: where it is from and what
/// it sounds like, which is how a listener picks between six results all
/// called "Jazz FM".
///
/// Public because the directory is drawn in two places, this dialog's
/// result list and search's Radio chip, and should read the same in both.
String? describeDirectoryEntry(RadioDirectoryEntry entry) {
  final parts = <String>[
    if (entry.country != null) entry.country!,
    if (entry.bitrateKbps != null && entry.bitrateKbps! > 0)
      '${entry.codec ?? 'stream'} ${entry.bitrateKbps} kbps',
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
          () =>
              _error = '${e.message} Paste a stream URL instead with "By URL".',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'A station needs a stream URL.');
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
        _error = 'A station needs a name.';
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
      // Inline, not a snackbar: this dialog stays open on a refusal, and a
      // snackbar would render behind it. A duplicate stream URL is the
      // refusal a listener hits most, so it is the one that must be
      // readable.
      if (mounted) setState(() => _error = e.message);
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
    return AlertDialog(
      title: Text(_editing ? 'Edit station' : 'Add station'),
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
                  label: 'How to add',
                  segments: const <WaxSegment>[
                    WaxSegment(name: 'search', label: 'Search'),
                    WaxSegment(name: 'url', label: 'By URL'),
                  ],
                  selected: _manual ? 'url' : 'search',
                  onSelect: (name) => setState(() => _manual = name == 'url'),
                ),
              const SizedBox(height: WaxSpace.s12),
              if (!_manual) ..._directory(colors) else ..._form(colors),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        WaxButton(
          label: 'Cancel',
          kind: WaxButtonKind.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (_manual)
          WaxButton(
            label: _editing ? 'Save changes' : 'Add',
            kind: WaxButtonKind.filled,
            semanticsId: SemanticsIds.radioAddConfirm,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
      ],
    );
  }

  /// Directory search with its results.
  List<Widget> _directory(WaxColors colors) => <Widget>[
    WaxTextField(
      label: 'Station name',
      controller: _search,
      glyph: WaxIcons.search,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => unawaited(_runSearch()),
      semanticsId: SemanticsIds.radioSearchField,
    ),
    const SizedBox(height: WaxSpace.s8),
    WaxButton(
      label: 'Search directory',
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
            ? const Padding(
                padding: EdgeInsets.all(WaxSpace.s12),
                child: Text('No matches'),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _results!.length,
                itemBuilder: (context, index) {
                  final entry = _results![index];
                  return WaxOptionRow(
                    title: entry.name,
                    subtitle: describeDirectoryEntry(entry),
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
  List<Widget> _form(WaxColors colors) => <Widget>[
    WaxTextField(
      label: 'Stream URL',
      controller: _url,
      hint: 'https://example.com/stream',
      autofocus: !_editing,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => unawaited(_save()),
      semanticsId: SemanticsIds.radioUrlField,
    ),
    const SizedBox(height: WaxSpace.s8),
    Align(
      alignment: Alignment.centerLeft,
      child: WaxButton(
        label: _details ? 'Fewer options' : 'Name, website, and logo',
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
        label: 'Station name',
        controller: _name,
        hint: 'Taken from the stream address when left blank',
        semanticsId: SemanticsIds.radioNameField,
      ),
      const SizedBox(height: WaxSpace.s8),
      WaxTextField(
        label: 'Website (optional)',
        controller: _homepage,
        semanticsId: SemanticsIds.radioHomepageField,
      ),
      const SizedBox(height: WaxSpace.s8),
      WaxTextField(
        label: 'Logo URL (optional)',
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

/// The name a pasted stream takes when nobody typed one.
///
/// The stream's host, which is what the listener would call it anyway
/// ("somafm.com"), minus a `www.` that says nothing. Deliberately the
/// whole host rather than a guess at the registrable part: without a
/// public-suffix list "bbc.co.uk" would come back as "co.uk", and a
/// station named after the wrong half of its own address is worse than
/// one named after all of it. It is a placeholder either way - the
/// station is editable the moment it exists.
String stationNameFromUrl(String url) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  final trimmed = host.startsWith('www.') ? host.substring(4) : host;
  return trimmed.isEmpty ? 'Station' : trimmed;
}
