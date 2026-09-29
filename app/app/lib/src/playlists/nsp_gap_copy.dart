import 'dart:convert';

import 'package:waxdeck_api/waxdeck_api.dart';

import '../l10n/l10n.dart';
import 'rule_vocabulary.dart';

/// A gap in the reader's language, worded from its code: an export names
/// fields and operators as the rule editor does, an import quotes the
/// document. A code this build does not know keeps the server's sentence.
String nspGapSentence(
  AppLocalizations l10n,
  NspGap gap, {
  required bool export,
}) {
  final quoted = l10n.playlistNspGapQuoted;
  String opWord(String op) => quoted(export ? ruleOpLabel(l10n, op) : op);
  final field = switch (gap.field) {
    null => '',
    final f when export => ruleFieldLabel(l10n, f),
    final f => quoted(f),
  };
  final op = gap.op == null ? '' : opWord(gap.op!);
  final key = quoted(gap.key ?? '');
  final value = _valueText(gap.value, quoted);
  String unit(String mode) => switch (mode) {
    'minutes' || 'megabytes' => ruleLimitUnit(l10n, mode),
    _ => quoted(mode),
  };
  return switch (gap.code) {
    'multiple_roots' => l10n.playlistNspGapMultipleRoots,
    'missing_root' => l10n.playlistNspGapMissingRoot,
    'group_not_array' => l10n.playlistNspGapGroupNotArray(key),
    'rule_shape' => l10n.playlistNspGapRuleShape,
    'operator_shape' => l10n.playlistNspGapOperatorShape(op),
    'days_not_number' => l10n.playlistNspGapDaysNotNumber(op, field),
    'range_shape' => l10n.playlistNspGapRangeShape(op, field),
    'bad_value' => l10n.playlistNspGapBadValue(op, field),
    'bad_limit' => l10n.playlistNspGapBadLimit,
    'bad_offset' => l10n.playlistNspGapBadOffset,
    'bad_sort' => l10n.playlistNspGapBadSort,
    'bad_order' => l10n.playlistNspGapBadOrder,
    'value_not_numeric' => l10n.playlistNspGapValueNotNumeric(field, value),
    'value_not_boolean' =>
      export
          ? l10n.playlistNspGapValueNotBooleanExport(field, value)
          : l10n.playlistNspGapValueNotBooleanImport(op, field, value),
    'unsupported_key' => l10n.playlistNspGapUnsupportedKey(key),
    'group_emptied' =>
      export
          ? l10n.playlistNspGapGroupEmptiedExport
          : l10n.playlistNspGapGroupEmptiedImport,
    'unsupported_node' => l10n.playlistNspGapUnsupportedNode,
    'negation' => l10n.playlistNspGapNegation,
    'unsupported_field' when export =>
      l10n.playlistNspGapUnsupportedFieldExport(field),
    // The name an older WaxDeck export gave the star.
    'unsupported_field' when gap.field?.toLowerCase() == 'starred' =>
      l10n.playlistNspGapStarredImport(field),
    'unsupported_field' => l10n.playlistNspGapUnsupportedFieldImport(field),
    'date_operator' =>
      export
          ? l10n.playlistNspGapDateOperatorExport(field)
          : l10n.playlistNspGapDateOperatorImport(op, field),
    'scaled_text_operator' =>
      export
          ? l10n.playlistNspGapScaledTextOperatorExport(field, op)
          : l10n.playlistNspGapScaledTextOperatorImport(field, op),
    'unsupported_operator' =>
      export
          ? l10n.playlistNspGapUnsupportedOperatorExport(op)
          : l10n.playlistNspGapUnsupportedOperatorImport(op, field),
    'boolean_operator' => l10n.playlistNspGapBooleanOperator(
      field,
      opWord('is'),
      opWord('isNot'),
    ),
    'presence_operator' =>
      export
          ? l10n.playlistNspGapPresenceOperatorExport(field, op)
          : l10n.playlistNspGapPresenceOperatorImport(op, field),
    'window_too_large' => l10n.playlistNspGapWindowTooLarge(value),
    'window_not_whole_days' =>
      export
          ? l10n.playlistNspGapWindowNotWholeDaysExport
          : l10n.playlistNspGapWindowNotWholeDaysImport(op, value),
    'rating_not_whole_star' => l10n.playlistNspGapRatingNotWholeStar(value),
    'duration_not_whole_ms' =>
      export
          ? l10n.playlistNspGapDurationNotWholeMsExport(field, value)
          : l10n.playlistNspGapDurationNotWholeMsImport(value),
    'value_too_large' => l10n.playlistNspGapValueTooLarge(value, field),
    'unsupported_sort_field' =>
      export
          ? l10n.playlistNspGapUnsupportedSortFieldExport(field)
          : l10n.playlistNspGapUnsupportedSortFieldImport(field),
    'random_with_sorts' => l10n.playlistNspGapRandomWithSorts,
    'extra_sort_term' => l10n.playlistNspGapExtraSortTerm(field),
    'random_needs_limit' =>
      export
          ? l10n.playlistNspGapRandomNeedsLimitExport
          : l10n.playlistNspGapRandomNeedsLimitImport,
    // The mode is the value here, and rides beside the limit on a budget.
    'limit_mode' => l10n.playlistNspGapLimitMode(unit('${gap.value}')),
    'limit_seed' => l10n.playlistNspGapLimitSeed,
    'limit_budget' => l10n.playlistNspGapLimitBudget(
      value,
      unit(gap.mode ?? ''),
    ),
    'entity_widens' => l10n.playlistNspGapEntityWidens,
    'entity_files' => l10n.playlistNspGapEntityFiles,
    _ => gap.reason,
  };
}

/// A value as the rule or the document wrote it, text quoted.
String _valueText(Object? value, String Function(String) quoted) =>
    switch (value) {
      null => '',
      final String s => quoted(s),
      final num n when n == n.truncateToDouble() && n.abs() < 1e15 =>
        n.toInt().toString(),
      final num n => n.toString(),
      final bool b => b.toString(),
      _ => jsonEncode(value),
    };
