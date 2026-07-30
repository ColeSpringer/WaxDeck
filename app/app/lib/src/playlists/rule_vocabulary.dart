/// How a smart rule reads on screen.
///
/// The wire's vocabulary is written for a machine (`albumArtist`, `gte`)
/// and stays that way, so the presentation lives here - in one place,
/// because the editor and the detail header read the same rule and would
/// otherwise drift.
library;

import 'package:waxdeck_api/waxdeck_api.dart';

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

/// `albumArtist` becomes "Album artist", `tag.mood` becomes "Tag: mood".
/// Derived rather than tabulated, so a field the server adds arrives
/// readable; a tag key is left as its owner typed it.
String ruleFieldLabel(String field) {
  if (field.startsWith(ruleTagPrefix)) {
    return 'Tag: ${field.substring(ruleTagPrefix.length)}';
  }
  if (field.isEmpty) return field;
  final words = field
      .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase();
  return words[0].toUpperCase() + words.substring(1);
}

/// An operator as a phrase, so a condition reads as a sentence.
const _opLabels = <String, String>{
  'is': 'is',
  'isNot': 'is not',
  'contains': 'contains',
  'startsWith': 'starts with',
  'endsWith': 'ends with',
  'isPresent': 'is set',
  'isMissing': 'is not set',
  'gt': 'is more than',
  'lt': 'is less than',
  'gte': 'is at least',
  'lte': 'is at most',
  'inTheRange': 'is between',
  'before': 'is before',
  'after': 'is after',
  'inTheLast': 'is in the last',
  'notInTheLast': 'is not in the last',
};

String ruleOpLabel(String op) => _opLabels[op] ?? op;

/// What the number beside a limit is counting.
String ruleLimitUnit(String limitMode) => switch (limitMode) {
  'minutes' => 'minutes',
  'megabytes' => 'MB',
  _ => 'items',
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

/// A condition value as it should read rather than as it rides.
///
/// Every value is a string on the wire, so its shape is the only signal:
/// an RFC 3339 instant is a date, and true/false under an equality is
/// the boolean the editor draws as yes and no. Off the value rather than
/// the field's kind because a summary has no vocabulary loaded.
String ruleValueLabel(String value, String op) {
  final at = DateTime.tryParse(value);
  if (at != null && value.contains('-')) {
    return at.toLocal().toString().split(' ').first;
  }
  if ((op == 'is' || op == 'isNot') && (value == 'true' || value == 'false')) {
    return value == 'true' ? 'yes' : 'no';
  }
  return value;
}

/// One condition as a phrase: "Genre is Rock", "Added in the last 90
/// days", "Rating is at least 80".
String describeCondition(RuleNode node) {
  final field = ruleFieldLabel(node.field ?? '');
  final op = node.op ?? '';
  if (ruleUnaryOps.contains(op)) return '$field ${ruleOpLabel(op)}';
  if (ruleRelativeOps.contains(op)) {
    final days = node.value ?? '';
    // "1 day", not "1 days".
    final unit = days == '1' ? 'day' : 'days';
    return '$field ${ruleOpLabel(op)} $days $unit';
  }
  if (op == 'inTheRange' && node.values.length > 1) {
    final low = ruleValueLabel(node.values[0], op);
    final high = ruleValueLabel(node.values[1], op);
    return '$field ${ruleOpLabel(op)} $low and $high';
  }
  final value = node.values.isNotEmpty ? node.values.first : (node.value ?? '');
  return '$field ${ruleOpLabel(op)} ${ruleValueLabel(value, op)}';
}

/// A rule as the chips the detail header shows: one per condition, then
/// the order, then the limit.
///
/// Flattened: a chip row is a glance, and a nested tree drawn as text is
/// neither a glance nor an accurate tree. A shape it cannot draw says so
/// in one chip rather than summarising half of it.
List<String> describeRule(SmartRule rule) {
  final chips = <String>[];
  // Unwrapped so all four of the editor's group modes summarise; the
  // lead chip carries the inversion.
  final negated = rule.root.type == 'not' && rule.root.node != null;
  final root = negated ? rule.root.node! : rule.root;
  final group = root.type == 'all' || root.type == 'any';
  final flat = group && root.nodes.every((n) => n.type == 'condition');
  if (flat) {
    final lead = switch ((negated, root.type == 'any')) {
      (false, true) => 'Any of',
      (true, true) => 'None of',
      (true, false) => 'Not all of',
      (false, false) => null,
    };
    if (lead != null && root.nodes.length > 1) chips.add(lead);
    // "None of" over a single chip reads as a heading, not a negation.
    if (negated && root.nodes.length == 1) chips.add('Not');
    for (final node in root.nodes) {
      chips.add(describeCondition(node));
    }
    if (root.nodes.isEmpty) {
      // An empty ALL matches everything and an empty ANY matches
      // nothing, and a negation swaps them.
      final everything = (root.type == 'all') != negated;
      chips.add(everything ? 'Everything' : 'Nothing');
    }
  } else if (root.type == 'condition') {
    chips.add(
      negated ? 'Not ${describeCondition(root)}' : describeCondition(root),
    );
  } else {
    chips.add('Nested conditions');
  }
  for (final sort in rule.sorts) {
    chips.add(
      'By ${ruleFieldLabel(sort.field).toLowerCase()}'
      '${sort.desc ? ', highest first' : ''}',
    );
  }
  if (rule.limit > 0) {
    chips.add(switch (rule.limitMode) {
      'random' => '${rule.limit} at random',
      'minutes' => 'Up to ${rule.limit} minutes',
      'megabytes' => 'Up to ${rule.limit} MB',
      _ => 'Limit ${rule.limit}',
    });
  }
  return chips;
}
