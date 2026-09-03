/// How a smart rule reads on screen. One place, because the editor and
/// the detail header read the same rule and would otherwise drift. The
/// table comes in as an argument: this is not widget code.
library;

import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';

/// The `tag.` prefix a custom tag key wears as a rule field.
const ruleTagPrefix = 'tag.';

/// Operators that take no value.
const ruleUnaryOps = <String>{'isPresent', 'isMissing'};

/// Operators whose value is a whole number of days back from now rather
/// than an absolute timestamp.
const ruleRelativeOps = <String>{'inTheLast', 'notInTheLast'};

/// What a tag field accepts; the endpoint documents the set once against
/// the text kind rather than per key.
const ruleTagOps = <String>[
  'is',
  'isNot',
  'contains',
  'startsWith',
  'endsWith',
  'isPresent',
  'isMissing',
];

/// Limit modes the editor can draw; `limitMode` is an open string, so a
/// future one opens read-only rather than breaking the picker.
const ruleKnownLimitModes = <String>{'', 'random', 'minutes', 'megabytes'};

/// What a rule field is called: `albumArtist` is "Album artist",
/// `tag.mood` is "Tag: mood". A field this build has never heard of
/// falls back to the derivation, which is readable and English.
String ruleFieldLabel(AppLocalizations l10n, String field) {
  if (field.startsWith(ruleTagPrefix)) {
    return l10n.playlistRuleTagField(field.substring(ruleTagPrefix.length));
  }
  // A switch rather than a map: this is called per dropdown entry per
  // rebuild, and the editor rebuilds on every keystroke.
  return switch (field) {
    'mediaType' => l10n.playlistRuleFieldMediaType,
    'title' => l10n.playlistRuleFieldTitle,
    'artist' => l10n.playlistRuleFieldArtist,
    'albumArtist' => l10n.playlistRuleFieldAlbumArtist,
    'album' => l10n.playlistRuleFieldAlbum,
    'podcast' => l10n.playlistRuleFieldPodcast,
    'genre' => l10n.playlistRuleFieldGenre,
    'year' => l10n.playlistRuleFieldYear,
    'trackNumber' => l10n.playlistRuleFieldTrackNumber,
    'discNumber' => l10n.playlistRuleFieldDiscNumber,
    'bpm' => l10n.playlistRuleFieldBpm,
    'season' => l10n.playlistRuleFieldSeason,
    'publishedAt' => l10n.playlistRuleFieldPublishedAt,
    'durationMs' => l10n.playlistRuleFieldDurationMs,
    'albumBarcode' => l10n.playlistRuleFieldAlbumBarcode,
    'albumLabel' => l10n.playlistRuleFieldAlbumLabel,
    'albumCatalogNumber' => l10n.playlistRuleFieldAlbumCatalogNumber,
    'albumMedia' => l10n.playlistRuleFieldAlbumMedia,
    'albumCountry' => l10n.playlistRuleFieldAlbumCountry,
    'source' => l10n.playlistRuleFieldSource,
    'codec' => l10n.playlistRuleFieldCodec,
    'container' => l10n.playlistRuleFieldContainer,
    'path' => l10n.playlistRuleFieldPath,
    'state' => l10n.playlistRuleFieldState,
    'addedAt' => l10n.playlistRuleFieldAddedAt,
    'updatedAt' => l10n.playlistRuleFieldUpdatedAt,
    'starred' => l10n.playlistRuleFieldStarred,
    'starredAt' => l10n.playlistRuleFieldStarredAt,
    'rating' => l10n.playlistRuleFieldRating,
    'playCount' => l10n.playlistRuleFieldPlayCount,
    'played' => l10n.playlistRuleFieldPlayed,
    'finished' => l10n.playlistRuleFieldFinished,
    'lastPlayedAt' => l10n.playlistRuleFieldLastPlayedAt,
    'playlist' => l10n.playlistRuleFieldPlaylist,
    _ => _derivedFieldLabel(field),
  };
}

/// `albumArtist` becomes "Album artist", for a field this build has
/// never heard of.
String _derivedFieldLabel(String field) {
  if (field.isEmpty) return field;
  final words = field
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase();
  return words[0].toUpperCase() + words.substring(1);
}

/// An operator as a phrase, so a condition reads as a sentence. An
/// operator the table does not know draws as its wire name, which is at
/// least the truth.
String ruleOpLabel(AppLocalizations l10n, String op) => switch (op) {
  'is' => l10n.playlistRuleOpIs,
  'isNot' => l10n.playlistRuleOpIsNot,
  'contains' => l10n.playlistRuleOpContains,
  'startsWith' => l10n.playlistRuleOpStartsWith,
  'endsWith' => l10n.playlistRuleOpEndsWith,
  'isPresent' => l10n.playlistRuleOpIsPresent,
  'isMissing' => l10n.playlistRuleOpIsMissing,
  'gt' => l10n.playlistRuleOpGt,
  'lt' => l10n.playlistRuleOpLt,
  'gte' => l10n.playlistRuleOpGte,
  'lte' => l10n.playlistRuleOpLte,
  'inTheRange' => l10n.playlistRuleOpInTheRange,
  'before' => l10n.playlistRuleOpBefore,
  'after' => l10n.playlistRuleOpAfter,
  'inTheLast' => l10n.playlistRuleOpInTheLast,
  'notInTheLast' => l10n.playlistRuleOpNotInTheLast,
  _ => op,
};

/// What the number beside a limit is counting.
String ruleLimitUnit(AppLocalizations l10n, String limitMode) =>
    switch (limitMode) {
      'minutes' => l10n.playlistRuleUnitMinutes,
      'megabytes' => l10n.playlistRuleUnitMegabytes,
      _ => l10n.playlistRuleUnitItems,
    };

/// The value kind of [field] in [vocabulary], defaulting to text for a
/// tag key or a field the catalogue no longer lists.
String ruleFieldKind(RuleFields vocabulary, String field) {
  if (field.startsWith(ruleTagPrefix)) return 'text';
  for (final f in vocabulary.fields) {
    if (f.name == field) return f.kind;
  }
  return 'text';
}

/// The operators [field] accepts.
List<String> ruleFieldOps(RuleFields vocabulary, String field) {
  if (field.startsWith(ruleTagPrefix)) return ruleTagOps;
  for (final f in vocabulary.fields) {
    if (f.name == field) return f.ops;
  }
  return const <String>['is'];
}

/// The prefix a playlist pid wears, which is how a rule value naming a
/// playlist is recognised without the vocabulary in hand.
const rulePlaylistPrefix = 'pl-';

/// Resolves a playlist pid to its name, or null when the caller cannot
/// see that list (it was deleted, or belongs to somebody else).
typedef PlaylistNameLookup = String? Function(String pid);

/// A condition value as it should read rather than as it rides.
///
/// Every value is a string on the wire, so its shape is the only signal:
/// an RFC 3339 instant is a date, true/false under an equality is the
/// boolean the editor draws as yes and no, and a `pl-` pid is a
/// playlist. Off the value rather than the field's kind because a
/// summary has no vocabulary loaded.
///
/// A playlist reads as its name where [playlistName] can supply one and
/// as its pid otherwise: a rule pointing at a deleted list still has to
/// say something, and the pid is the only true thing left to say.
String ruleValueLabel(
  AppLocalizations l10n,
  String value,
  String op, {
  PlaylistNameLookup? playlistName,
}) {
  if (value.startsWith(rulePlaylistPrefix)) {
    return playlistName?.call(value) ?? value;
  }
  final at = DateTime.tryParse(value);
  if (at != null && value.contains('-')) return l10n.formatDate(at);
  if ((op == 'is' || op == 'isNot') && (value == 'true' || value == 'false')) {
    return value == 'true' ? l10n.playlistRuleYes : l10n.playlistRuleNo;
  }
  return value;
}

/// One condition as a phrase: "Genre is Rock", "Added in the last 90
/// days", "Rating is at least 80".
String describeCondition(
  AppLocalizations l10n,
  RuleNode node, {
  PlaylistNameLookup? playlistName,
}) {
  final field = ruleFieldLabel(l10n, node.field ?? '');
  final op = node.op ?? '';
  final phrase = ruleOpLabel(l10n, op);
  if (ruleUnaryOps.contains(op)) {
    return l10n.playlistRuleConditionUnary(field, phrase);
  }
  if (ruleRelativeOps.contains(op)) {
    final raw = node.value ?? '';
    // Worded where it is a number, kept as it stands where it is not:
    // the value rides as a string and a draft in progress can hold
    // anything at all.
    final days = int.tryParse(raw);
    return l10n.playlistRuleConditionRelative(
      field,
      phrase,
      days == null ? raw : l10n.playlistRuleDayCount(days),
    );
  }
  if (op == 'inTheRange' && node.values.length > 1) {
    return l10n.playlistRuleConditionRange(
      field,
      phrase,
      ruleValueLabel(l10n, node.values[0], op),
      ruleValueLabel(l10n, node.values[1], op),
    );
  }
  final value = node.values.isNotEmpty ? node.values.first : (node.value ?? '');
  // A media type reads the way its picker draws it. Keyed on the field
  // rather than on the value, which `ruleValueLabel` only ever sees on
  // its own: a genre called "music" is not a media type.
  final worded = node.field == 'mediaType'
      ? l10n.playlistRuleMediaType(value)
      : ruleValueLabel(l10n, value, op, playlistName: playlistName);
  return l10n.playlistRuleCondition(field, phrase, worded);
}

/// A rule as the chips the detail header shows: one per condition, then
/// the order, then the limit.
///
/// Flattened: a chip row is a glance, and a nested tree drawn as text is
/// neither a glance nor an accurate tree. A shape it cannot draw says so
/// in one chip rather than summarising half of it.
List<String> describeRule(
  AppLocalizations l10n,
  SmartRule rule, {
  PlaylistNameLookup? playlistName,
}) {
  final chips = <String>[];
  // Unwrapped so all four of the editor's group modes summarise; the
  // lead chip carries the inversion.
  final negated = rule.root.type == 'not' && rule.root.node != null;
  final root = negated ? rule.root.node! : rule.root;
  final group = root.type == 'all' || root.type == 'any';
  final flat = group && root.nodes.every((n) => n.type == 'condition');
  if (flat) {
    final lead = switch ((negated, root.type == 'any')) {
      (false, true) => l10n.playlistRuleAnyOf,
      (true, true) => l10n.playlistRuleNoneOf,
      (true, false) => l10n.playlistRuleNotAllOf,
      (false, false) => null,
    };
    if (lead != null && root.nodes.length > 1) chips.add(lead);
    // "None of" over a single chip reads as a heading, not a negation.
    if (negated && root.nodes.length == 1) chips.add(l10n.playlistRuleNot);
    for (final node in root.nodes) {
      chips.add(describeCondition(l10n, node, playlistName: playlistName));
    }
    if (root.nodes.isEmpty) {
      // An empty ALL matches everything and an empty ANY matches
      // nothing, and a negation swaps them.
      final everything = (root.type == 'all') != negated;
      chips.add(
        everything ? l10n.playlistRuleEverything : l10n.playlistRuleNothing,
      );
    }
  } else if (root.type == 'condition') {
    final phrase = describeCondition(l10n, root, playlistName: playlistName);
    chips.add(negated ? l10n.playlistRuleNotPhrase(phrase) : phrase);
  } else {
    chips.add(l10n.playlistRuleNested);
  }
  for (final sort in rule.sorts) {
    // The field's own label, drawn as it is: lower-casing it was an
    // English rule about mid-sentence nouns, and the chip is a label
    // rather than a sentence.
    final field = ruleFieldLabel(l10n, sort.field);
    chips.add(
      sort.desc
          ? l10n.playlistRuleSortByDesc(field)
          : l10n.playlistRuleSortBy(field),
    );
  }
  if (rule.limit > 0) {
    chips.add(switch (rule.limitMode) {
      'random' => l10n.playlistRuleLimitRandom(rule.limit),
      'minutes' => l10n.playlistRuleLimitMinutes(rule.limit),
      'megabytes' => l10n.playlistRuleLimitMegabytes(rule.limit),
      _ => l10n.playlistRuleLimitCount(rule.limit),
    });
  }
  return chips;
}
