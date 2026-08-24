import 'package:waxdeck_api/waxdeck_api.dart';
import 'package:waxdeck_ui/waxdeck_ui.dart';

import '../l10n/l10n.dart';
import '../shell/semantics_ids.dart';
import 'metadata_controller.dart';

/// The editor's shared form layer: the staged-edit model and the typed
/// rows drawn from it. The item editor owns one draft today; the
/// release workbench mounts the same layer over its selection when it
/// lands.
///
/// Everything here stages. The one save bar commits the whole draft,
/// so no section carries a write button of its own, and a change is
/// dirty state the bar counts rather than a request already sent.

/// What one editable field is called in the reader's language.
///
/// The vocabulary arrives from the server as wire keys - `album_artist`,
/// `track_no` - which were only ever an accessible name until the field
/// began drawing its label. A lookup rather than an enum because the
/// server owns the list, and the key itself is the fallback: a field a
/// later server adds draws its own name rather than nothing, and
/// translating it is one line here.
String metadataFieldLabel(AppLocalizations l10n, String name) => switch (name) {
  'title' => l10n.metadataFieldTitle,
  'artist' => l10n.metadataFieldArtist,
  'album_artist' => l10n.metadataFieldAlbumArtist,
  'album' => l10n.metadataFieldAlbum,
  'composer' => l10n.metadataFieldComposer,
  'composer_sort' => l10n.metadataFieldComposerSort,
  'comment' => l10n.metadataFieldComment,
  'genre' => l10n.metadataFieldGenre,
  'year' => l10n.metadataFieldYear,
  'track_no' => l10n.metadataFieldTrackNo,
  'disc_no' => l10n.metadataFieldDiscNo,
  'isrc' => l10n.metadataFieldIsrc,
  'mbid' => l10n.metadataFieldMbid,
  'compilation' => l10n.metadataFieldCompilation,
  'author' => l10n.metadataFieldAuthor,
  'author_sort' => l10n.metadataFieldAuthorSort,
  'narrator' => l10n.metadataFieldNarrator,
  'series' => l10n.metadataFieldSeries,
  'subtitle' => l10n.metadataFieldSubtitle,
  'asin' => l10n.metadataFieldAsin,
  'isbn' => l10n.metadataFieldIsbn,
  'publisher' => l10n.metadataFieldPublisher,
  'edition' => l10n.metadataFieldEdition,
  'description' => l10n.metadataFieldDescription,
  'pinned' => l10n.metadataFieldPinned,
  'season' => l10n.metadataFieldSeason,
  'episode_no' => l10n.metadataFieldEpisodeNo,
  'episode_type' => l10n.metadataFieldEpisodeType,
  'explicit' => l10n.metadataFieldExplicit,
  'link' => l10n.metadataFieldLink,
  _ => name,
};

/// What one credit role is called, with the same fallback rule as
/// [metadataFieldLabel]: the server owns the vocabulary, and an unknown
/// role draws its wire name rather than nothing.
String metadataRoleLabel(AppLocalizations l10n, String role) => switch (role) {
  'composer' => l10n.metadataRoleComposer,
  'lyricist' => l10n.metadataRoleLyricist,
  'conductor' => l10n.metadataRoleConductor,
  'performer' => l10n.metadataRolePerformer,
  'remixer' => l10n.metadataRoleRemixer,
  'producer' => l10n.metadataRoleProducer,
  'engineer' => l10n.metadataRoleEngineer,
  'mixer' => l10n.metadataRoleMixer,
  'arranger' => l10n.metadataRoleArranger,
  'writer' => l10n.metadataRoleWriter,
  'djmixer' => l10n.metadataRoleDjmixer,
  'author' => l10n.metadataRoleAuthor,
  'narrator' => l10n.metadataRoleNarrator,
  'translator' => l10n.metadataRoleTranslator,
  'editor' => l10n.metadataRoleEditor,
  _ => role,
};

/// How one field is edited. The wire carries every value as a string;
/// the type says what control stands in front of that string.
enum MetadataFieldType { text, count, toggle, genres, choice }

MetadataFieldType metadataFieldType(String name) => switch (name) {
  'year' ||
  'track_no' ||
  'disc_no' ||
  'season' ||
  'episode_no' => MetadataFieldType.count,
  'compilation' || 'explicit' || 'pinned' => MetadataFieldType.toggle,
  'genre' => MetadataFieldType.genres,
  'episode_type' => MetadataFieldType.choice,
  _ => MetadataFieldType.text,
};

/// The closed vocabulary behind a choice field, with the value an empty
/// store means first. The server refuses anything else
/// (`episode_type must be full|trailer|bonus`), so a free text box here
/// was a refusal of the whole unified save waiting to be typed.
List<String> metadataChoiceOptions(String name) => switch (name) {
  'episode_type' => const ['full', 'trailer', 'bonus'],
  _ => const [],
};

/// What one choice value is called. The values are the server's own
/// vocabulary; unknowns draw themselves, like the field labels do.
String metadataChoiceLabel(AppLocalizations l10n, String value) =>
    switch (value) {
      'full' => l10n.metadataEpisodeTypeFull,
      'trailer' => l10n.metadataEpisodeTypeTrailer,
      'bonus' => l10n.metadataEpisodeTypeBonus,
      _ => value,
    };

/// Reads a stored choice value, folding absence onto the default the
/// server folds an empty value onto.
String metadataWireChoice(String name, String? stored) {
  final value = (stored ?? '').trim();
  return value.isEmpty ? metadataChoiceOptions(name).first : value;
}

/// Reads a stored boolean field the way the catalog writes one. The
/// vocabulary mirrors the server's own parse; absent is false, which is
/// what the server means by omitting the field.
bool metadataWireBool(String? value) =>
    switch ((value ?? '').trim().toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' || 'y' || 't' => true,
      _ => false,
    };

/// Splits a stored genre display string the way the catalog splits a
/// genre tag, dropping duplicates case-insensitively.
List<String> splitMetadataGenres(String raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final part in raw.split(RegExp(r'[;/\\]'))) {
    final name = part.trim();
    if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
    out.add(name);
  }
  return out;
}

/// Joins staged genres back into the wire's display string. The
/// semicolon is one of the separators the catalog splits on, so the
/// value round-trips.
String joinMetadataGenres(List<String> genres) => genres.join('; ');

/// The catalog canonicalizes tag keys (trimmed, ASCII uppercased)
/// before storing them, so the client stages the canonical form: a key
/// staged as typed would never match the stored row it comes back as,
/// and the draft would offer the same write for ever.
String canonicalMetadataTagKey(String key) => key.trim().toUpperCase();

/// One timed-lyrics stamp, as the preview and the wire split decide it.
final metadataLrcStamp = RegExp(r'^\s*\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$');

/// Whether lyrics text carries any timed line. Timed text goes to the
/// server as LRC; plain text must go as plain, because the LRC parser
/// drops unstamped lines and then refuses the empty result.
bool metadataLyricsTimed(String text) =>
    text.split('\n').any(metadataLrcStamp.hasMatch);

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Everything the draft would write, measured against what is stored.
/// The save bar counts it and the controller commits it.
class MetadataChanges {
  const MetadataChanges({
    this.fields = const {},
    this.credits = const {},
    this.lyrics,
    this.clearLyrics = false,
    this.tagSets = const {},
    this.tagRemoves = const [],
    this.unofficial,
  });

  /// Scalar fields, serialized for the wire (a toggle as `true`/`false`,
  /// the genres joined).
  final Map<String, String> fields;

  /// Credit roles whose name list changed; an empty list clears the role.
  final Map<String, List<String>> credits;

  /// Replacement lyrics, or null when they did not change.
  final String? lyrics;

  /// Whether the stored lyrics are removed (the field was emptied).
  final bool clearLyrics;

  final Map<String, List<String>> tagSets;
  final List<String> tagRemoves;

  /// The new release status, or null when it did not change.
  final bool? unofficial;

  int get count =>
      fields.length +
      credits.length +
      (lyrics != null || clearLyrics ? 1 : 0) +
      tagSets.length +
      tagRemoves.length +
      (unofficial != null ? 1 : 0);

  bool get isEmpty => count == 0;
}

/// The staged edits behind the form: what has been typed, toggled, and
/// picked but not yet saved.
///
/// Every part keeps the same three-way rule the text fields always had:
/// what is staged, what it was seeded with from the server, and what the
/// server holds now. Staged equal to seeded means nobody touched it, so
/// a refetch may adopt the fresh value; staged different from seeded is
/// the user's and outranks the refetch. After a save the refetch echoes
/// what was written, staged and stored agree again, and the draft reads
/// clean without anything being reset by hand.
class MetadataDraft extends ChangeNotifier {
  final _controllers = <String, TextEditingController>{};
  final _seeded = <String, String>{};
  final _toggles = <String, bool>{};
  final _seededToggles = <String, bool>{};
  final _choices = <String, String>{};
  final _seededChoices = <String, String>{};
  List<String>? _genres;
  List<String> _seededGenres = const [];
  final _credits = <String, List<String>>{};
  final _seededCredits = <String, List<String>>{};
  final lyrics = TextEditingController();
  var _lyricsSeeded = false;
  String _seededLyrics = '';
  bool? _unofficial;
  bool _seededUnofficial = false;
  final _tagSets = <String, List<String>>{};
  final _tagRemoves = <String>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    lyrics.dispose();
    super.dispose();
  }

  /// The controller for a text or count field, seeded on first sight.
  TextEditingController controllerFor(String field, String initial) {
    return _controllers.putIfAbsent(field, () {
      _seeded[field] = initial;
      final controller = TextEditingController(text: initial);
      // Recompute dirtiness (and the save bar) as the user types.
      controller.addListener(notifyListeners);
      return controller;
    });
  }

  bool toggleValue(String field, String? stored) {
    final value = metadataWireBool(stored);
    _seededToggles.putIfAbsent(field, () => value);
    return _toggles.putIfAbsent(field, () => value);
  }

  void setToggle(String field, {required bool value}) {
    _toggles[field] = value;
    notifyListeners();
  }

  String choiceValue(String field, String? stored) {
    final value = metadataWireChoice(field, stored);
    _seededChoices.putIfAbsent(field, () => value);
    return _choices.putIfAbsent(field, () => value);
  }

  void setChoice(String field, String value) {
    _choices[field] = value;
    notifyListeners();
  }

  List<String> genresValue(String? stored) {
    if (_genres == null) {
      _seededGenres = splitMetadataGenres(stored ?? '');
      _genres = List.of(_seededGenres);
    }
    return _genres!;
  }

  void setGenres(List<String> genres) {
    _genres = List.of(genres);
    notifyListeners();
  }

  void removeGenre(String name) {
    _genres?.remove(name);
    notifyListeners();
  }

  /// The staged names for one role, seeded from what is stored.
  List<String> creditNames(String role, List<String> stored) {
    _seededCredits.putIfAbsent(role, () => List.of(stored));
    return _credits.putIfAbsent(role, () => List.of(stored));
  }

  void addCredits(String role, List<String> stored, Iterable<String> names) {
    final list = creditNames(role, stored);
    for (final name in names) {
      if (name.isNotEmpty && !list.contains(name)) list.add(name);
    }
    notifyListeners();
  }

  void removeCredit(String role, String name) {
    _credits[role]?.remove(name);
    notifyListeners();
  }

  String lyricsValue(String stored) {
    if (!_lyricsSeeded) {
      _lyricsSeeded = true;
      _seededLyrics = stored;
      lyrics.text = stored;
      lyrics.addListener(notifyListeners);
    }
    return lyrics.text;
  }

  bool unofficialValue({required bool stored}) {
    // Seeded once here; only [adopt] re-seeds after that. Re-seeding on
    // every build read the not-yet-refreshed store during a save and
    // let the refetch overwrite a flip made while it was in flight.
    if (_unofficial == null) {
      _unofficial = stored;
      _seededUnofficial = stored;
    }
    return _unofficial!;
  }

  void setUnofficial({required bool value}) {
    _unofficial = value;
    notifyListeners();
  }

  bool tagRemovalStaged(String key) => _tagRemoves.contains(key);

  List<String>? tagSetStaged(String key) => _tagSets[key];

  /// The staged-but-unstored tags, for the rows the stored list lacks.
  Iterable<MapEntry<String, List<String>>> newTags(
    Iterable<String> storedKeys,
  ) {
    final stored = storedKeys.toSet();
    return _tagSets.entries.where((e) => !stored.contains(e.key));
  }

  void stageTag(String key, List<String> values) {
    // Canonical from the start, so the staged entry matches the stored
    // row the server echoes it back as.
    final canonical = canonicalMetadataTagKey(key);
    _tagSets[canonical] = List.of(values);
    _tagRemoves.remove(canonical);
    notifyListeners();
  }

  void stageTagRemove(String key, {required bool stored}) {
    _tagSets.remove(key);
    if (stored) _tagRemoves.add(key);
    notifyListeners();
  }

  void unstageTagRemove(String key) {
    _tagRemoves.remove(key);
    notifyListeners();
  }

  /// Takes server-side changes into the parts nobody is editing.
  /// Without it a fetched title is invisible and reads as a local edit,
  /// so Save offers to write the stale text back over it.
  void adopt(MetadataEditorState state) {
    for (final field in state.kindFields.fields) {
      final stored = state.metadata.fields[field.name];
      switch (metadataFieldType(field.name)) {
        case MetadataFieldType.text || MetadataFieldType.count:
          final controller = _controllers[field.name];
          if (controller == null) continue;
          final text = stored ?? '';
          // Already in agreement - the usual case after a save, which
          // echoes back what was written. Re-seed so the next genuine
          // change is still recognised as one.
          if (controller.text == text) {
            _seeded[field.name] = text;
            continue;
          }
          // Typed in since it was seeded: that edit is the user's and
          // outranks a refetch.
          if (controller.text != _seeded[field.name]) continue;
          _seeded[field.name] = text;
          controller.text = text;
        case MetadataFieldType.toggle:
          final value = metadataWireBool(stored);
          final staged = _toggles[field.name];
          if (staged == null || staged == value) {
            _toggles[field.name] = value;
            _seededToggles[field.name] = value;
            continue;
          }
          if (staged != _seededToggles[field.name]) continue;
          _toggles[field.name] = value;
          _seededToggles[field.name] = value;
        case MetadataFieldType.choice:
          final value = metadataWireChoice(field.name, stored);
          final staged = _choices[field.name];
          if (staged == null || staged == value) {
            _choices[field.name] = value;
            _seededChoices[field.name] = value;
            continue;
          }
          if (staged != _seededChoices[field.name]) continue;
          _choices[field.name] = value;
          _seededChoices[field.name] = value;
        case MetadataFieldType.genres:
          final value = splitMetadataGenres(stored ?? '');
          final staged = _genres;
          if (staged == null || _sameList(staged, value)) {
            _genres = List.of(value);
            _seededGenres = value;
            continue;
          }
          if (!_sameList(staged, _seededGenres)) continue;
          _genres = List.of(value);
          _seededGenres = value;
      }
    }

    final storedCredits = {
      for (final credit in state.metadata.credits) credit.role: credit.names,
    };
    for (final role in {..._credits.keys, ...storedCredits.keys}) {
      final stored = storedCredits[role] ?? const <String>[];
      final staged = _credits[role];
      if (staged == null || _sameList(staged, stored)) {
        _credits[role] = List.of(stored);
        _seededCredits[role] = List.of(stored);
        continue;
      }
      final seeded = _seededCredits[role];
      if (seeded == null || !_sameList(staged, seeded)) continue;
      _credits[role] = List.of(stored);
      _seededCredits[role] = List.of(stored);
    }

    final storedLrc = state.metadata.lyrics?.lrc ?? '';
    if (!_lyricsSeeded) {
      // Left for [lyricsValue]: seeding here would miss the listener.
    } else if (lyrics.text == storedLrc) {
      _seededLyrics = storedLrc;
    } else if (lyrics.text.trim() == storedLrc.trim() ||
        lyrics.text.trim() == _seededLyrics.trim()) {
      // Trim-equal counts as agreement and trim-equal-to-seeded as
      // untouched: a stray space in an empty box must not outrank
      // fetched lyrics (and then offer to delete them), and the trim
      // half is also what lets a saved value settle onto the server's
      // normalized echo.
      _seededLyrics = storedLrc;
      lyrics.text = storedLrc;
    }

    final storedUnofficial = state.metadata.unofficial;
    if (_unofficial == null ||
        _unofficial == storedUnofficial ||
        _unofficial == _seededUnofficial) {
      _unofficial = storedUnofficial;
      _seededUnofficial = storedUnofficial;
    }

    // Tag staging is a delta, so anything the store now reflects is no
    // longer a change to make.
    final storedTags = {
      for (final tag in state.metadata.customTags) tag.key: tag.values,
    };
    _tagSets.removeWhere(
      (key, values) => _sameList(storedTags[key] ?? const <String>[], values),
    );
    _tagRemoves.removeWhere((key) => !storedTags.containsKey(key));
  }

  /// Everything staged that differs from what [state] holds.
  MetadataChanges changes(MetadataEditorState state) {
    final fields = <String, String>{};
    for (final field in state.kindFields.fields) {
      final stored = state.metadata.fields[field.name];
      switch (metadataFieldType(field.name)) {
        case MetadataFieldType.text || MetadataFieldType.count:
          final controller = _controllers[field.name];
          if (controller != null && controller.text != (stored ?? '')) {
            fields[field.name] = controller.text;
          }
        case MetadataFieldType.toggle:
          final staged = _toggles[field.name];
          if (staged != null && staged != metadataWireBool(stored)) {
            fields[field.name] = staged ? 'true' : 'false';
          }
        case MetadataFieldType.genres:
          final staged = _genres;
          if (staged != null &&
              !_sameList(staged, splitMetadataGenres(stored ?? ''))) {
            fields[field.name] = joinMetadataGenres(staged);
          }
        case MetadataFieldType.choice:
          final staged = _choices[field.name];
          if (staged != null &&
              staged != metadataWireChoice(field.name, stored)) {
            fields[field.name] = staged;
          }
      }
    }

    final credits = <String, List<String>>{};
    final storedCredits = {
      for (final credit in state.metadata.credits) credit.role: credit.names,
    };
    for (final entry in _credits.entries) {
      final stored = storedCredits[entry.key] ?? const <String>[];
      if (!_sameList(entry.value, stored)) {
        credits[entry.key] = List.of(entry.value);
      }
    }

    String? newLyrics;
    var clearLyrics = false;
    final storedLrc = state.metadata.lyrics?.lrc ?? '';
    // Trim-compared, like adopt: whitespace-only differences are not a
    // change to write, and a bare space over an empty store must never
    // read as one.
    if (_lyricsSeeded && lyrics.text.trim() != storedLrc.trim()) {
      if (lyrics.text.trim().isEmpty) {
        clearLyrics = state.metadata.lyrics != null;
      } else {
        newLyrics = lyrics.text;
      }
    }

    final storedTags = {
      for (final tag in state.metadata.customTags) tag.key: tag.values,
    };
    final tagSets = <String, List<String>>{};
    for (final entry in _tagSets.entries) {
      if (!_sameList(storedTags[entry.key] ?? const <String>[], entry.value)) {
        tagSets[entry.key] = List.of(entry.value);
      }
    }
    final tagRemoves = _tagRemoves.where(storedTags.containsKey).toList();

    final unofficial =
        _unofficial != null && _unofficial != state.metadata.unofficial
        ? _unofficial
        : null;

    return MetadataChanges(
      fields: fields,
      credits: credits,
      lyrics: newLyrics,
      clearLyrics: clearLyrics,
      tagSets: tagSets,
      tagRemoves: tagRemoves,
      unofficial: unofficial,
    );
  }

  /// Re-seeds every part a save committed with exactly what was sent.
  ///
  /// Load-bearing where the server normalizes: send `Title ` and the
  /// refetch echoes `Title`, so staged, stored, and the pre-save seed
  /// are three different strings - and the untouched rule reads that as
  /// an edit in flight and refuses to adopt. Seeded to what was sent,
  /// the field counts as untouched and settles onto the echo; the same
  /// discipline the album editor applies for the same reason. Called
  /// only on a save that fully committed - after a refusal, the parts
  /// that did not land must stay the user's.
  void markSaved(MetadataChanges changes) {
    for (final entry in changes.fields.entries) {
      switch (metadataFieldType(entry.key)) {
        case MetadataFieldType.text || MetadataFieldType.count:
          if (_controllers.containsKey(entry.key)) {
            _seeded[entry.key] = entry.value;
          }
        case MetadataFieldType.toggle:
          _seededToggles[entry.key] = entry.value == 'true';
        case MetadataFieldType.genres:
          _seededGenres = List.of(_genres ?? const []);
        case MetadataFieldType.choice:
          _seededChoices[entry.key] = entry.value;
      }
    }
    for (final entry in changes.credits.entries) {
      _seededCredits[entry.key] = List.of(entry.value);
    }
    if (changes.lyrics != null || changes.clearLyrics) {
      _seededLyrics = lyrics.text;
    }
    if (changes.unofficial case final sent?) {
      _seededUnofficial = sent;
    }
    // Tags need nothing: they stage as deltas, and adopt drops every
    // entry the refetched store reflects.
  }
}

/// One field row: the typed control for the value, the provenance chip,
/// and the lock toggle. The chip and the lock are the part of the old
/// form worth keeping, so every type keeps them.
class MetadataFieldRow extends StatelessWidget {
  const MetadataFieldRow({
    super.key,
    required this.field,
    required this.state,
    required this.draft,
    required this.dirty,
    required this.busy,
    required this.onToggleLock,
    this.onAddGenre,
  });

  final EditableField field;
  final MetadataEditorState state;
  final MetadataDraft draft;

  /// Whether this field differs from what is stored. Marked on the
  /// field rather than only counted on the save bar, so a long form
  /// says which line is about to be written.
  final bool dirty;

  /// Whether a save is in flight. The staging controls disable for its
  /// duration: a toggle flipped back mid-save reads as untouched once
  /// the refetch lands, and the second decision would be discarded.
  final bool busy;

  final VoidCallback onToggleLock;

  /// Opens the genre picker; only the genres row uses it. The caller
  /// owns the sheet because the canonical tree is its read.
  final VoidCallback? onAddGenre;

  String _provenanceText(AppLocalizations l10n) {
    final p = state.provenanceFor(field.name);
    if (p == null) return l10n.metadataSourceUnknown;
    final provider = p.provider;
    return provider == null
        ? p.source
        : l10n.metadataSourceWithProvider(p.source, provider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final locked = state.isLocked(field.name);
    final marks = Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s8),
      child: Row(
        children: <Widget>[
          CodecChip(_provenanceText(l10n), emphasis: dirty),
          WaxIconButton(
            glyph: locked ? WaxIcons.bookmark : WaxIcons.edit,
            label: locked
                ? l10n.metadataUnlockField(field.name)
                : l10n.metadataLockField(field.name),
            active: locked,
            size: 16,
            color: locked ? colors.accent : null,
            semanticsId: SemanticsIds.fieldLock(field.name),
            onPressed: onToggleLock,
          ),
        ],
      ),
    );
    final stored = state.metadata.fields[field.name];
    final control = switch (metadataFieldType(field.name)) {
      MetadataFieldType.text => WaxTextField(
        label: metadataFieldLabel(l10n, field.name),
        controller: draft.controllerFor(field.name, stored ?? ''),
        semanticsId: SemanticsIds.metadataField(field.name),
      ),
      MetadataFieldType.count => WaxTextField(
        label: metadataFieldLabel(l10n, field.name),
        controller: draft.controllerFor(field.name, stored ?? ''),
        digitsOnly: true,
        semanticsId: SemanticsIds.metadataField(field.name),
      ),
      MetadataFieldType.toggle => Padding(
        padding: const EdgeInsetsDirectional.only(start: WaxSpace.s12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: ExcludeSemantics(
                // The switch carries this exact string as its own name.
                child: Text(
                  metadataFieldLabel(l10n, field.name),
                  style: WaxType.body.copyWith(color: colors.textPrimary),
                ),
              ),
            ),
            WaxSwitch(
              label: metadataFieldLabel(l10n, field.name),
              value: draft.toggleValue(field.name, stored),
              semanticsId: SemanticsIds.metadataField(field.name),
              onChanged: busy
                  ? null
                  : (v) => draft.setToggle(field.name, value: v),
            ),
          ],
        ),
      ),
      MetadataFieldType.genres => _GenreChips(
        label: metadataFieldLabel(l10n, field.name),
        genres: draft.genresValue(stored),
        onRemove: busy ? null : draft.removeGenre,
        onAdd: busy ? null : onAddGenre,
      ),
      MetadataFieldType.choice => WaxChoice<String>(
        label: metadataFieldLabel(l10n, field.name),
        value: draft.choiceValue(field.name, stored),
        semanticsId: SemanticsIds.metadataField(field.name),
        options: metadataChoiceOptions(field.name),
        labelFor: (value) => metadataChoiceLabel(l10n, value),
        onChanged: busy ? null : (v) => draft.setChoice(field.name, v),
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(child: control),
        const SizedBox(width: WaxSpace.s8),
        marks,
      ],
    );
  }
}

/// The staged genres as removable chips, with the picker behind Add.
class _GenreChips extends StatelessWidget {
  const _GenreChips({
    required this.label,
    required this.genres,
    required this.onRemove,
    required this.onAdd,
  });

  final String label;
  final List<String> genres;

  /// Null while a save is in flight, which disables every chip.
  final ValueChanged<String>? onRemove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.only(
            bottom: WaxSpace.s4,
            start: WaxSpace.s12,
          ),
          child: ExcludeSemantics(
            child: Text(
              label,
              style: WaxType.label.copyWith(color: colors.textSecondary),
            ),
          ),
        ),
        Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.metadataField('genre'),
          child: Wrap(
            spacing: WaxSpace.s8,
            runSpacing: WaxSpace.s8,
            children: <Widget>[
              for (final name in genres)
                RemovableChip(
                  text: name,
                  label: l10n.metadataRemoveGenre(name),
                  semanticsId: SemanticsIds.metadataGenreRemove(name),
                  onRemove: switch (onRemove) {
                    final remove? => () => remove(name),
                    null => null,
                  },
                ),
              WaxPill(
                label: l10n.metadataAddGenre,
                semanticsId: SemanticsIds.metadataGenreAdd,
                onPressed: onAdd,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A staged value drawn as a chip whose press removes it. The close
/// glyph says what the tap does; the accessible name says it in words.
class RemovableChip extends StatelessWidget {
  const RemovableChip({
    super.key,
    required this.text,
    required this.label,
    required this.onRemove,
    this.semanticsId,
  });

  final String text;

  /// The accessible name, a sentence about the removal.
  final String label;

  final VoidCallback? onRemove;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return WaxTappable(
      semanticsId: semanticsId,
      label: label,
      borderRadius: WaxRadius.pill,
      onPressed: onRemove,
      child: Ink(
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: WaxRadius.pill,
          border: Border.all(color: colors.hairline),
        ),
        child: InkWell(
          borderRadius: WaxRadius.pill,
          onTap: onRemove,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s12,
              vertical: WaxSpace.s8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  text,
                  style: WaxType.caption.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(width: WaxSpace.s4),
                WaxIcon(WaxIcons.close, size: 14, color: colors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks genres over the canonical tree. [tree] may be empty - the
/// vocabulary read is administrators-only - and the sheet then takes
/// genres as typed, which every caller may do anyway.
Future<List<String>?> showMetadataGenrePicker(
  BuildContext context, {
  required List<GenreNode> tree,
  required List<String> selected,
}) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _GenrePickerSheet(tree: tree, selected: selected),
);

class _GenrePickerSheet extends StatefulWidget {
  const _GenrePickerSheet({required this.tree, required this.selected});

  final List<GenreNode> tree;
  final List<String> selected;

  @override
  State<_GenrePickerSheet> createState() => _GenrePickerSheetState();
}

class _GenrePickerSheetState extends State<_GenrePickerSheet> {
  late final List<String> _selected = List.of(widget.selected);
  late final Set<String> _selectedLower = {
    for (final name in _selected) name.toLowerCase(),
  };
  final _query = TextEditingController();

  /// The tree flattened once - it never changes while the sheet is up -
  /// in reading order: each top-level genre, then its children indented
  /// under it. Selected off-tree genres are appended per build (they
  /// change with every toggle) so they can be toggled off from here too.
  late final List<({String name, bool child})> _treeOptions = _flatten();
  late final Set<String> _treeLower = {
    for (final option in _treeOptions) option.name.toLowerCase(),
  };

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<({String name, bool child})> _flatten() {
    final out = <({String name, bool child})>[];
    final children = <String, List<String>>{};
    final tops = <String>[];
    for (final node in widget.tree) {
      final parent = node.parent;
      if (parent == null || parent.isEmpty) {
        tops.add(node.name);
      } else {
        (children[parent] ??= []).add(node.name);
      }
    }
    for (final top in tops) {
      out.add((name: top, child: false));
      for (final name in children.remove(top) ?? const <String>[]) {
        out.add((name: name, child: true));
      }
    }
    // A parent that is not itself listed top-level; the server refuses
    // storing one, but drawing it flat beats dropping it.
    for (final orphans in children.values) {
      for (final name in orphans) {
        out.add((name: name, child: false));
      }
    }
    return out;
  }

  List<({String name, bool child})> _options() => [
    ..._treeOptions,
    for (final name in _selected)
      if (!_treeLower.contains(name.toLowerCase())) (name: name, child: false),
  ];

  void _toggle(String name) {
    setState(() {
      final lower = name.toLowerCase();
      if (_selectedLower.remove(lower)) {
        _selected.removeWhere((g) => g.toLowerCase() == lower);
      } else {
        _selected.add(name);
        _selectedLower.add(lower);
      }
    });
  }

  /// Stages typed text, split the way the catalog splits a genre tag:
  /// `Singer/Songwriter` is two genres to the store, and staging it as
  /// one would come back split and read as dirty for ever.
  void _addTyped(String query) {
    setState(() {
      for (final name in splitMetadataGenres(query)) {
        final lower = name.toLowerCase();
        if (_selectedLower.add(lower)) _selected.add(name);
      }
    });
    _query.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final query = _query.text.trim();
    final options = _options()
        .where(
          (o) =>
              query.isEmpty ||
              o.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final exact = options.any(
      (o) => o.name.toLowerCase() == query.toLowerCase(),
    );
    return Padding(
      // Over the keyboard, which the entry field raises.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.metadataGenrePicker,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: WaxSpace.s16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
                  child: Text(
                    l10n.metadataGenrePickerTitle,
                    style: WaxType.headline.copyWith(color: colors.textPrimary),
                  ),
                ),
                const SizedBox(height: WaxSpace.s8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
                  child: WaxTextField(
                    label: l10n.metadataGenreSearchHint,
                    hint: l10n.metadataGenreSearchHint,
                    showLabel: false,
                    glyph: WaxIcons.search,
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    semanticsId: SemanticsIds.metadataGenrePickerSearch,
                  ),
                ),
                if (query.isNotEmpty && !exact)
                  _OptionRow(
                    text: l10n.metadataGenreAddCustom(query),
                    child: false,
                    selected: false,
                    semanticsId: SemanticsIds.metadataGenrePickerCustom,
                    onPressed: () => _addTyped(query),
                  ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options[index];
                      return _OptionRow(
                        text: option.name,
                        child: option.child,
                        selected: _selectedLower.contains(
                          option.name.toLowerCase(),
                        ),
                        semanticsId: SemanticsIds.metadataGenreOption(
                          option.name,
                        ),
                        onPressed: () => _toggle(option.name),
                      );
                    },
                  ),
                ),
                const SizedBox(height: WaxSpace.s8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WaxSpace.s16),
                  child: WaxButton(
                    label: l10n.commonDone,
                    semanticsId: SemanticsIds.metadataGenrePickerApply,
                    onPressed: () => Navigator.of(context).pop(_selected),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.text,
    required this.child,
    required this.selected,
    required this.onPressed,
    this.semanticsId,
  });

  final String text;

  /// Whether this genre groups under the one above it, drawn as an
  /// indent.
  final bool child;

  final bool selected;
  final VoidCallback onPressed;
  final String? semanticsId;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    return WaxTappable(
      semanticsId: semanticsId,
      label: text,
      selected: selected,
      onPressed: onPressed,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: child ? WaxSpace.s32 : WaxSpace.s16,
            end: WaxSpace.s16,
            top: WaxSpace.s8,
            bottom: WaxSpace.s8,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  text,
                  style: WaxType.body.copyWith(color: colors.textPrimary),
                ),
              ),
              if (selected)
                WaxIcon(
                  WaxIcons.check,
                  size: 16,
                  color: colors.accent,
                  active: true,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The credits, as chips per role. Only the vocabulary's roles take
/// edits here - a stored role outside it (a track's `artist` credit)
/// is drawn read-only, because its sanctioned edit path is the scalar
/// field that resolves it.
class MetadataCreditsSection extends StatefulWidget {
  const MetadataCreditsSection({
    super.key,
    required this.state,
    required this.draft,
    required this.busy,
  });

  final MetadataEditorState state;
  final MetadataDraft draft;
  final bool busy;

  @override
  State<MetadataCreditsSection> createState() => _MetadataCreditsSectionState();
}

class _MetadataCreditsSectionState extends State<MetadataCreditsSection> {
  final _names = TextEditingController();
  String? _role;

  @override
  void dispose() {
    _names.dispose();
    super.dispose();
  }

  void _add(String role, List<String> stored) {
    final names = _names.text
        .split(',')
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return;
    widget.draft.addCredits(role, stored, names);
    _names.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final state = widget.state;
    final draft = widget.draft;
    final roles = state.kindFields.creditRoles;
    final role = _role ?? (roles.isEmpty ? null : roles.first.name);
    final storedByRole = {
      for (final credit in state.metadata.credits) credit.role: credit.names,
    };
    final vocabulary = {for (final r in roles) r.name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.metadataCreditsTitle,
          overline: l10n.metadataCreditsOverline,
        ),
        for (final credit in state.metadata.credits)
          if (!vocabulary.contains(credit.role))
            Padding(
              padding: const EdgeInsets.only(bottom: WaxSpace.s4),
              child: MonoDetailRow(
                label: metadataRoleLabel(l10n, credit.role),
                value: credit.names.join(', '),
              ),
            ),
        for (final r in roles)
          _roleGroup(
            context,
            r.name,
            draft.creditNames(r.name, storedByRole[r.name] ?? const []),
            storedByRole[r.name] ?? const [],
          ),
        if (roles.isEmpty)
          Text(
            l10n.metadataNoCreditRoles,
            style: WaxType.bodySmall.copyWith(color: colors.textTertiary),
          )
        else ...<Widget>[
          const SizedBox(height: WaxSpace.s8),
          WaxChoice<String>(
            label: l10n.metadataCreditRole,
            value: role!,
            semanticsId: SemanticsIds.creditsRole,
            options: <String>[for (final r in roles) r.name],
            labelFor: (name) => metadataRoleLabel(l10n, name),
            onChanged: (v) => setState(() => _role = v),
          ),
          const SizedBox(height: WaxSpace.s8),
          WaxTextField(
            label: l10n.metadataCreditNames,
            controller: _names,
            semanticsId: SemanticsIds.creditsNames,
            onSubmitted: (_) => _add(role, storedByRole[role] ?? const []),
          ),
          const SizedBox(height: WaxSpace.s8),
          WaxButton(
            label: l10n.metadataAddCredit,
            kind: WaxButtonKind.tonal,
            icon: WaxIcons.add,
            semanticsId: SemanticsIds.creditAdd,
            onPressed: widget.busy
                ? null
                : () => _add(role, storedByRole[role] ?? const []),
          ),
        ],
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }

  Widget _roleGroup(
    BuildContext context,
    String role,
    List<String> names,
    List<String> stored,
  ) {
    if (names.isEmpty && stored.isEmpty) return const SizedBox.shrink();
    final colors = WaxColors.of(context);
    final l10n = context.l10n;
    final dirty = !_sameList(names, stored);
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                metadataRoleLabel(l10n, role),
                style: WaxType.label.copyWith(color: colors.textSecondary),
              ),
              if (dirty) ...<Widget>[
                const SizedBox(width: WaxSpace.s8),
                CodecChip(l10n.metadataPendingChip, emphasis: true),
              ],
            ],
          ),
          const SizedBox(height: WaxSpace.s4),
          Wrap(
            spacing: WaxSpace.s8,
            runSpacing: WaxSpace.s8,
            children: <Widget>[
              for (final name in names)
                RemovableChip(
                  text: name,
                  label: l10n.metadataRemoveCredit(name),
                  semanticsId: SemanticsIds.creditRemove(role, name),
                  onRemove: widget.busy
                      ? null
                      : () => widget.draft.removeCredit(role, name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The custom tags, staged like everything else: Add and the remove
/// buttons mark the draft, and the save bar is what writes.
class MetadataTagsSection extends StatefulWidget {
  const MetadataTagsSection({
    super.key,
    required this.state,
    required this.draft,
    required this.busy,
  });

  final MetadataEditorState state;
  final MetadataDraft draft;
  final bool busy;

  @override
  State<MetadataTagsSection> createState() => _MetadataTagsSectionState();
}

class _MetadataTagsSectionState extends State<MetadataTagsSection> {
  final _key = TextEditingController();
  final _values = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    _values.dispose();
    super.dispose();
  }

  void _add() {
    final key = _key.text.trim();
    final values = _values.text
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    // Both halves or nothing: a tag with no values stages as a row the
    // change count cannot see, which is a chip that says "Unsaved" over
    // a save bar that stays off.
    if (key.isEmpty || values.isEmpty) return;
    widget.draft.stageTag(key, values);
    _key.clear();
    _values.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final draft = widget.draft;
    final storedKeys = <String>[
      for (final tag in state.metadata.customTags) tag.key,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionHeader(
          title: l10n.metadataTagsTitle,
          overline: l10n.metadataTagsOverline,
        ),
        for (final tag in state.metadata.customTags)
          _tagRow(
            context,
            tag.key,
            draft.tagSetStaged(tag.key) ?? tag.values,
            staged: draft.tagSetStaged(tag.key) != null,
            removalStaged: draft.tagRemovalStaged(tag.key),
            stored: true,
          ),
        for (final entry in draft.newTags(storedKeys))
          _tagRow(
            context,
            entry.key,
            entry.value,
            staged: true,
            removalStaged: false,
            stored: false,
          ),
        const SizedBox(height: WaxSpace.s8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            SizedBox(
              width: 140,
              child: WaxTextField(
                label: l10n.metadataTagKey,
                controller: _key,
                semanticsId: SemanticsIds.tagKey,
              ),
            ),
            const SizedBox(width: WaxSpace.s8),
            Expanded(
              child: WaxTextField(
                label: l10n.metadataTagValues,
                controller: _values,
                semanticsId: SemanticsIds.tagValues,
              ),
            ),
          ],
        ),
        const SizedBox(height: WaxSpace.s8),
        WaxButton(
          label: l10n.metadataAddTag,
          kind: WaxButtonKind.tonal,
          icon: WaxIcons.add,
          semanticsId: SemanticsIds.tagAdd,
          onPressed: widget.busy ? null : _add,
        ),
        const SizedBox(height: WaxSpace.s32),
      ],
    );
  }

  Widget _tagRow(
    BuildContext context,
    String key,
    List<String> values, {
    required bool staged,
    required bool removalStaged,
    required bool stored,
  }) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: WaxSpace.s4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: MonoDetailRow(label: key, value: values.join(', ')),
          ),
          if (removalStaged) ...<Widget>[
            CodecChip(l10n.metadataTagStagedRemove, emphasis: true),
            WaxIconButton(
              glyph: WaxIcons.refresh,
              label: l10n.metadataRestoreTag(key),
              size: 16,
              semanticsId: SemanticsIds.tagRestore(key),
              onPressed: widget.busy
                  ? null
                  : () => widget.draft.unstageTagRemove(key),
            ),
          ] else ...<Widget>[
            if (staged) CodecChip(l10n.metadataPendingChip, emphasis: true),
            WaxIconButton(
              glyph: WaxIcons.close,
              label: l10n.metadataRemoveTag(key),
              size: 16,
              semanticsId: SemanticsIds.tagRemove(key),
              onPressed: widget.busy
                  ? null
                  : () => widget.draft.stageTagRemove(key, stored: stored),
            ),
          ],
        ],
      ),
    );
  }
}

/// The sticky save bar: what is staged, and the one button that commits
/// it. The write-back warning sits beside it rather than at the top of
/// the form, so a partial tag write is read where the next save is
/// decided.
class MetadataSaveBar extends StatelessWidget {
  const MetadataSaveBar({
    super.key,
    required this.count,
    required this.busy,
    required this.onSave,
    this.writeBackFailures = const [],
    this.onDismissFailures,
  });

  final int count;
  final bool busy;
  final VoidCallback onSave;
  final List<WriteBackFailure> writeBackFailures;
  final VoidCallback? onDismissFailures;

  @override
  Widget build(BuildContext context) {
    final colors = WaxColors.of(context);
    final layout = WaxLayout.of(context);
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(
          top: BorderSide(color: colors.hairline, width: layout.hairlineWidth),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: SemanticsIds.metadataSaveBar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WaxSpace.s16,
              vertical: WaxSpace.s12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (writeBackFailures.isNotEmpty) ...<Widget>[
                  WaxBanner(
                    message: l10n.metadataWriteBackWarning,
                    tone: WaxBannerTone.caution,
                    semanticsId: SemanticsIds.metadataWritebackWarning,
                    onDismiss: onDismissFailures,
                  ),
                  const SizedBox(height: WaxSpace.s8),
                  // Which file and why is the content of the warning, so
                  // it stays on screen rather than passing as a message.
                  // Bounded: this slot sits outside the page's scroll,
                  // and a library box with forty unreachable files must
                  // not push the form (and Save itself) off screen.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: writeBackFailures.length,
                      itemBuilder: (context, index) {
                        final failure = writeBackFailures[index];
                        return Text(
                          l10n.metadataWriteBackFailure(
                            failure.path ?? failure.filePid,
                            failure.reason,
                          ),
                          style: WaxType.monoData.copyWith(
                            color: colors.textSecondary,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: WaxSpace.s8),
                ],
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: WaxButton(
                    label: count == 0
                        ? l10n.commonSave
                        : l10n.metadataSaveChanges(count),
                    icon: WaxIcons.check,
                    semanticsId: SemanticsIds.metadataSave,
                    onPressed: count == 0 || busy ? null : onSave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
