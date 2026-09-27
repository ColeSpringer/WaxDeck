import 'dart:convert';

import 'package:built_value/serializer.dart' show FullType;
import 'package:waxdeck_api_gen/waxdeck_api_gen.dart' as gen;

import 'mapping.dart';
import 'models.dart';

/// The fields [to] changed from [from], each at its value in [to] as the
/// wire spells it; a field [to] no longer holds is named with null.
///
/// What a preference change made offline waits as. Sent later over the
/// document as it stands then ([applyPrefsPatch]), it changes only what
/// the listener changed, where the whole document would put back every
/// field another device moved in the meantime. Spelled through the
/// generated serializers, so a field added to the contract is in the
/// patch without anyone listing it here.
///
/// A field that is an object (the browse sorts) is merged, not replaced,
/// so its patch names only the keys that changed, and a key it lost as
/// null: another device's sort for another dimension is not this
/// change's to overwrite.
Map<String, Object?> prefsPatch(Prefs from, Prefs to) =>
    _diff(_toJson(from), _toJson(to));

Map<String, Object?> _diff(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  final patch = <String, Object?>{};
  for (final key in {...before.keys, ...after.keys}) {
    final was = before[key];
    final now = after[key];
    if (was is Map && now is Map) {
      final inner = _diff(was.cast(), now.cast());
      if (inner.isNotEmpty) patch[key] = inner;
    } else if (_canonical(was) != _canonical(now)) {
      patch[key] = now;
    }
  }
  return patch;
}

/// What is left of [waiting] once [settled] was sent or refused: the
/// fields [settled] does not name, and those whose value moved on since.
///
/// A patch can grow while it is out, merged with a change made in the
/// meantime; this is the part of it that has not been answered yet.
Map<String, Object?> unsettledPrefsPatch(
  Map<String, Object?> waiting,
  Map<String, Object?> settled,
) {
  final left = <String, Object?>{};
  for (final MapEntry(:key, :value) in waiting.entries) {
    final sent = settled[key];
    if (value is Map && sent is Map) {
      final inner = unsettledPrefsPatch(value.cast(), sent.cast());
      if (inner.isNotEmpty) left[key] = inner;
    } else if (!settled.containsKey(key) ||
        _canonical(sent) != _canonical(value)) {
      left[key] = value;
    }
  }
  return left;
}

/// [earlier] and [later] as one patch, [later]'s values winning, and an
/// object in both merged key by key.
Map<String, Object?> mergePrefsPatches(
  Map<String, Object?> earlier,
  Map<String, Object?> later,
) {
  final merged = Map<String, Object?>.of(earlier);
  later.forEach((key, value) {
    final prior = merged[key];
    merged[key] = value is Map && prior is Map
        ? mergePrefsPatches(prior.cast(), value.cast())
        : value;
  });
  return merged;
}

/// [base] with every field [patch] names set to the patch's value, every
/// field it names with null cleared, and an object merged key by key.
Prefs applyPrefsPatch(Prefs base, Map<String, Object?> patch) => prefsFromGen(
  gen.standardSerializers.deserialize(
        _laid(_toJson(base), patch),
        specifiedType: const FullType(gen.Prefs),
      )
      as gen.Prefs,
);

Map<String, Object?> _laid(
  Map<String, Object?> json,
  Map<String, Object?> patch,
) {
  final laid = Map<String, Object?>.of(json);
  patch.forEach((key, value) {
    final current = laid[key];
    if (value == null) {
      laid.remove(key);
    } else if (value is Map) {
      laid[key] = _laid(
        current is Map ? current.cast() : const {},
        value.cast(),
      );
    } else {
      laid[key] = value;
    }
  });
  return laid;
}

Map<String, Object?> _toJson(Prefs prefs) => Map<String, Object?>.from(
  gen.standardSerializers.serialize(
        prefsToGen(prefs),
        specifiedType: const FullType(gen.Prefs),
      )
      as Map,
);

/// A value as text with every map's keys in order, so two equal values
/// compare equal however they were built.
String _canonical(Object? value) {
  Object? sorted(Object? v) => switch (v) {
    final Map<Object?, Object?> map => {
      for (final key in map.keys.map((k) => '$k').toList()..sort())
        key: sorted(map[key]),
    },
    final List<Object?> list => [for (final e in list) sorted(e)],
    _ => v,
  };
  return jsonEncode(sorted(value));
}
