// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_rule_count.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const HealthRuleCountFixBlockedEnum
_$healthRuleCountFixBlockedEnum_needsContact =
    const HealthRuleCountFixBlockedEnum._('needsContact');
const HealthRuleCountFixBlockedEnum
_$healthRuleCountFixBlockedEnum_needsLyricsSource =
    const HealthRuleCountFixBlockedEnum._('needsLyricsSource');
const HealthRuleCountFixBlockedEnum
_$healthRuleCountFixBlockedEnum_needsArtSource =
    const HealthRuleCountFixBlockedEnum._('needsArtSource');
const HealthRuleCountFixBlockedEnum
_$healthRuleCountFixBlockedEnum_needsGenreSource =
    const HealthRuleCountFixBlockedEnum._('needsGenreSource');
const HealthRuleCountFixBlockedEnum
_$healthRuleCountFixBlockedEnum_needsBookSource =
    const HealthRuleCountFixBlockedEnum._('needsBookSource');
const HealthRuleCountFixBlockedEnum
_$healthRuleCountFixBlockedEnum_noManagedLibrary =
    const HealthRuleCountFixBlockedEnum._('noManagedLibrary');
const HealthRuleCountFixBlockedEnum _$healthRuleCountFixBlockedEnum_readOnly =
    const HealthRuleCountFixBlockedEnum._('readOnly');
const HealthRuleCountFixBlockedEnum
_$healthRuleCountFixBlockedEnum_unknownDefaultOpenApi =
    const HealthRuleCountFixBlockedEnum._('unknownDefaultOpenApi');

HealthRuleCountFixBlockedEnum _$healthRuleCountFixBlockedEnumValueOf(
  String name,
) {
  switch (name) {
    case 'needsContact':
      return _$healthRuleCountFixBlockedEnum_needsContact;
    case 'needsLyricsSource':
      return _$healthRuleCountFixBlockedEnum_needsLyricsSource;
    case 'needsArtSource':
      return _$healthRuleCountFixBlockedEnum_needsArtSource;
    case 'needsGenreSource':
      return _$healthRuleCountFixBlockedEnum_needsGenreSource;
    case 'needsBookSource':
      return _$healthRuleCountFixBlockedEnum_needsBookSource;
    case 'noManagedLibrary':
      return _$healthRuleCountFixBlockedEnum_noManagedLibrary;
    case 'readOnly':
      return _$healthRuleCountFixBlockedEnum_readOnly;
    case 'unknownDefaultOpenApi':
      return _$healthRuleCountFixBlockedEnum_unknownDefaultOpenApi;
    default:
      return _$healthRuleCountFixBlockedEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<HealthRuleCountFixBlockedEnum>
_$healthRuleCountFixBlockedEnumValues = BuiltSet<HealthRuleCountFixBlockedEnum>(
  const <HealthRuleCountFixBlockedEnum>[
    _$healthRuleCountFixBlockedEnum_needsContact,
    _$healthRuleCountFixBlockedEnum_needsLyricsSource,
    _$healthRuleCountFixBlockedEnum_needsArtSource,
    _$healthRuleCountFixBlockedEnum_needsGenreSource,
    _$healthRuleCountFixBlockedEnum_needsBookSource,
    _$healthRuleCountFixBlockedEnum_noManagedLibrary,
    _$healthRuleCountFixBlockedEnum_readOnly,
    _$healthRuleCountFixBlockedEnum_unknownDefaultOpenApi,
  ],
);

Serializer<HealthRuleCountFixBlockedEnum>
_$healthRuleCountFixBlockedEnumSerializer =
    _$HealthRuleCountFixBlockedEnumSerializer();

class _$HealthRuleCountFixBlockedEnumSerializer
    implements PrimitiveSerializer<HealthRuleCountFixBlockedEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'needsContact': 'needs-contact',
    'needsLyricsSource': 'needs-lyrics-source',
    'needsArtSource': 'needs-art-source',
    'needsGenreSource': 'needs-genre-source',
    'needsBookSource': 'needs-book-source',
    'noManagedLibrary': 'no-managed-library',
    'readOnly': 'read-only',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'needs-contact': 'needsContact',
    'needs-lyrics-source': 'needsLyricsSource',
    'needs-art-source': 'needsArtSource',
    'needs-genre-source': 'needsGenreSource',
    'needs-book-source': 'needsBookSource',
    'no-managed-library': 'noManagedLibrary',
    'read-only': 'readOnly',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[HealthRuleCountFixBlockedEnum];
  @override
  final String wireName = 'HealthRuleCountFixBlockedEnum';

  @override
  Object serialize(
    Serializers serializers,
    HealthRuleCountFixBlockedEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  HealthRuleCountFixBlockedEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => HealthRuleCountFixBlockedEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$HealthRuleCount extends HealthRuleCount {
  @override
  final String rule;
  @override
  final String? label;
  @override
  final int failing;
  @override
  final bool fixable;
  @override
  final bool fixing;
  @override
  final HealthRuleCountFixBlockedEnum? fixBlocked;

  factory _$HealthRuleCount([void Function(HealthRuleCountBuilder)? updates]) =>
      (HealthRuleCountBuilder()..update(updates))._build();

  _$HealthRuleCount._({
    required this.rule,
    this.label,
    required this.failing,
    required this.fixable,
    required this.fixing,
    this.fixBlocked,
  }) : super._();
  @override
  HealthRuleCount rebuild(void Function(HealthRuleCountBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthRuleCountBuilder toBuilder() => HealthRuleCountBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthRuleCount &&
        rule == other.rule &&
        label == other.label &&
        failing == other.failing &&
        fixable == other.fixable &&
        fixing == other.fixing &&
        fixBlocked == other.fixBlocked;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, rule.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, failing.hashCode);
    _$hash = $jc(_$hash, fixable.hashCode);
    _$hash = $jc(_$hash, fixing.hashCode);
    _$hash = $jc(_$hash, fixBlocked.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthRuleCount')
          ..add('rule', rule)
          ..add('label', label)
          ..add('failing', failing)
          ..add('fixable', fixable)
          ..add('fixing', fixing)
          ..add('fixBlocked', fixBlocked))
        .toString();
  }
}

class HealthRuleCountBuilder
    implements Builder<HealthRuleCount, HealthRuleCountBuilder> {
  _$HealthRuleCount? _$v;

  String? _rule;
  String? get rule => _$this._rule;
  set rule(String? rule) => _$this._rule = rule;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  int? _failing;
  int? get failing => _$this._failing;
  set failing(int? failing) => _$this._failing = failing;

  bool? _fixable;
  bool? get fixable => _$this._fixable;
  set fixable(bool? fixable) => _$this._fixable = fixable;

  bool? _fixing;
  bool? get fixing => _$this._fixing;
  set fixing(bool? fixing) => _$this._fixing = fixing;

  HealthRuleCountFixBlockedEnum? _fixBlocked;
  HealthRuleCountFixBlockedEnum? get fixBlocked => _$this._fixBlocked;
  set fixBlocked(HealthRuleCountFixBlockedEnum? fixBlocked) =>
      _$this._fixBlocked = fixBlocked;

  HealthRuleCountBuilder() {
    HealthRuleCount._defaults(this);
  }

  HealthRuleCountBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _rule = $v.rule;
      _label = $v.label;
      _failing = $v.failing;
      _fixable = $v.fixable;
      _fixing = $v.fixing;
      _fixBlocked = $v.fixBlocked;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthRuleCount other) {
    _$v = other as _$HealthRuleCount;
  }

  @override
  void update(void Function(HealthRuleCountBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthRuleCount build() => _build();

  _$HealthRuleCount _build() {
    final _$result =
        _$v ??
        _$HealthRuleCount._(
          rule: BuiltValueNullFieldError.checkNotNull(
            rule,
            r'HealthRuleCount',
            'rule',
          ),
          label: label,
          failing: BuiltValueNullFieldError.checkNotNull(
            failing,
            r'HealthRuleCount',
            'failing',
          ),
          fixable: BuiltValueNullFieldError.checkNotNull(
            fixable,
            r'HealthRuleCount',
            'fixable',
          ),
          fixing: BuiltValueNullFieldError.checkNotNull(
            fixing,
            r'HealthRuleCount',
            'fixing',
          ),
          fixBlocked: fixBlocked,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
