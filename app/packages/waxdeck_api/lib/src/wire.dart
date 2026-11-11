/// What the generated JSON codec calls: reads that check each value's
/// shape and name the field when it is wrong, the date and base64
/// conversions, and the list and map decoders.
///
/// Internal to this package, like the codec itself.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'models.dart' show WaxDeckApiException, apiErrorFromWire;

/// What a decode needs beyond the JSON itself.
class WireContext {
  const WireContext({required this.baseUrl});

  /// What media URLs resolve against ([resolveMediaUrl]).
  final String baseUrl;
}

/// Joins an origin-relative media [url] onto [baseUrl].
///
/// With an empty base (web builds) the URL stays relative and the browser
/// resolves it against the origin serving the SPA. Absolute URLs pass
/// through untouched.
String resolveMediaUrl(String baseUrl, String url) {
  if (baseUrl.isEmpty) return url;
  if (url.contains('://')) return url;
  // The client trims its base once, so the regex runs only for a context
  // built with a trailing slash.
  final base = baseUrl.endsWith('/')
      ? baseUrl.replaceAll(RegExp(r'/+$'), '')
      : baseUrl;
  return url.startsWith('/') ? '$base$url' : '$base/$url';
}

/// Reads one JSON value as a [T]; [at] names the value in errors.
typedef WireRead<T> = T Function(Object? value, String at);

/// [json]'s [key] through [read]; absent or null fails, naming [type]
/// and [key].
T readRequired<T>(
  Map<String, Object?> json,
  String key,
  String type,
  WireRead<T> read,
) {
  final value = json[key];
  if (value == null) {
    final what = json.containsKey(key) ? 'null' : 'missing';
    throw FormatException('$type.$key: $what');
  }
  return read(value, '$type.$key');
}

/// [json]'s [key] through [read], or null when absent or null (or when
/// [read] answers null).
T? readOptional<T>(
  Map<String, Object?> json,
  String key,
  String type,
  WireRead<T?> read,
) {
  final value = json[key];
  return value == null ? null : read(value, '$type.$key');
}

FormatException _shape(String at, String expected, Object? value) =>
    FormatException('$at: expected $expected, got ${value.runtimeType}');

String wireString(Object? value, String at) =>
    value is String ? value : throw _shape(at, 'a string', value);

int wireInt(Object? value, String at) =>
    value is int ? value : throw _shape(at, 'an integer', value);

/// A JSON number, whole ones included, as a double.
double wireDouble(Object? value, String at) =>
    value is num ? value.toDouble() : throw _shape(at, 'a number', value);

bool wireBool(Object? value, String at) =>
    value is bool ? value : throw _shape(at, 'a boolean', value);

Map<String, Object?> wireObject(Object? value, String at) =>
    value is Map<String, Object?>
    ? value
    : throw _shape(at, 'an object', value);

/// An RFC 3339 timestamp, in UTC.
DateTime wireDateTime(Object? value, String at) {
  final text = wireString(value, at);
  final parsed = DateTime.tryParse(text);
  if (parsed == null) throw FormatException('$at: not a date-time', text);
  return parsed.toUtc();
}

/// A full date (`2024-05-01`) as that day's midnight UTC.
DateTime wireDate(Object? value, String at) {
  final text = wireString(value, at);
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (match != null) {
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final date = DateTime.utc(year, month, day);
    if (date.month == month && date.day == day) return date;
  }
  throw FormatException('$at: not a date', text);
}

Uint8List wireBytes(Object? value, String at) {
  final text = wireString(value, at);
  try {
    return base64Decode(text);
  } on FormatException {
    throw FormatException('$at: not base64', text);
  }
}

/// A JSON list through [each]. An element [keep] refuses is dropped
/// unread.
List<T> wireList<T>(
  Object? value,
  String at,
  WireRead<T> each, {
  bool Function(Object? element)? keep,
}) {
  if (value is! List<Object?>) throw _shape(at, 'a list', value);
  return [
    for (var i = 0; i < value.length; i++)
      if (keep == null || keep(value[i])) each(value[i], '$at[$i]'),
  ];
}

/// A JSON object's values through [each].
Map<String, T> wireMap<T>(Object? value, String at, WireRead<T> each) {
  final object = wireObject(value, at);
  return {
    for (final entry in object.entries)
      entry.key: each(entry.value, '$at.${entry.key}'),
  };
}

/// A wire spelling as the member [fromWire] gives it; one it does not
/// know fails.
T wireEnum<T extends Object>(
  Object? value,
  String at,
  T? Function(String wire) fromWire,
) {
  final wire = wireString(value, at);
  return fromWire(wire) ?? (throw FormatException('$at: unknown value', wire));
}

/// Whether [value] is a spelling in [known]; anything but a string is
/// left for its decode to refuse.
bool wireKnown(Object? value, Set<String> known) =>
    value is! String || known.contains(value);

/// A string, or [fallback] for one outside [known].
String wireKnownOr(
  Object? value,
  String at,
  Set<String> known,
  String fallback,
) {
  final text = wireString(value, at);
  return known.contains(text) ? text : fallback;
}

/// A string, an empty one read as null.
String? wireNonEmpty(Object? value, String at) {
  final text = wireString(value, at);
  return text.isEmpty ? null : text;
}

/// A whole number of milliseconds.
Duration wireMilliseconds(Object? value, String at) =>
    Duration(milliseconds: wireInt(value, at));

/// The spec's `Error` object as the exception the client throws. It
/// carries no status code: it arrived inside an answer that succeeded.
WaxDeckApiException wireApiError(Object? value, String at) {
  final json = wireObject(value, at);
  // Read first so a failure names the member; the two strings are what
  // apiErrorFromWire needs, so it cannot answer null after them.
  readRequired(json, 'code', at, wireString);
  readRequired(json, 'message', at, wireString);
  return apiErrorFromWire(json)!;
}

/// [value]'s calendar date as the wire spells one: `2024-05-01`.
String writeDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String writeBytes(Uint8List value) => base64Encode(value);

Map<String, Object?> writeApiError(WaxDeckApiException value) => {
  'code': value.code,
  'message': value.message,
  'params': ?value.params,
};
