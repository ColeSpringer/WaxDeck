// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organize_hold.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_collision =
    const OrganizeHoldCodeEnum._('collision');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_occupied =
    const OrganizeHoldCodeEnum._('occupied');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_occupiedCase =
    const OrganizeHoldCodeEnum._('occupiedCase');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_untagged =
    const OrganizeHoldCodeEnum._('untagged');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_missing =
    const OrganizeHoldCodeEnum._('missing');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_virtual =
    const OrganizeHoldCodeEnum._('virtual');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_bookHeld =
    const OrganizeHoldCodeEnum._('bookHeld');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_readOnly =
    const OrganizeHoldCodeEnum._('readOnly');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_movedSince =
    const OrganizeHoldCodeEnum._('movedSince');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_uncataloged =
    const OrganizeHoldCodeEnum._('uncataloged');
const OrganizeHoldCodeEnum _$organizeHoldCodeEnum_unknownDefaultOpenApi =
    const OrganizeHoldCodeEnum._('unknownDefaultOpenApi');

OrganizeHoldCodeEnum _$organizeHoldCodeEnumValueOf(String name) {
  switch (name) {
    case 'collision':
      return _$organizeHoldCodeEnum_collision;
    case 'occupied':
      return _$organizeHoldCodeEnum_occupied;
    case 'occupiedCase':
      return _$organizeHoldCodeEnum_occupiedCase;
    case 'untagged':
      return _$organizeHoldCodeEnum_untagged;
    case 'missing':
      return _$organizeHoldCodeEnum_missing;
    case 'virtual':
      return _$organizeHoldCodeEnum_virtual;
    case 'bookHeld':
      return _$organizeHoldCodeEnum_bookHeld;
    case 'readOnly':
      return _$organizeHoldCodeEnum_readOnly;
    case 'movedSince':
      return _$organizeHoldCodeEnum_movedSince;
    case 'uncataloged':
      return _$organizeHoldCodeEnum_uncataloged;
    case 'unknownDefaultOpenApi':
      return _$organizeHoldCodeEnum_unknownDefaultOpenApi;
    default:
      return _$organizeHoldCodeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<OrganizeHoldCodeEnum> _$organizeHoldCodeEnumValues =
    BuiltSet<OrganizeHoldCodeEnum>(const <OrganizeHoldCodeEnum>[
      _$organizeHoldCodeEnum_collision,
      _$organizeHoldCodeEnum_occupied,
      _$organizeHoldCodeEnum_occupiedCase,
      _$organizeHoldCodeEnum_untagged,
      _$organizeHoldCodeEnum_missing,
      _$organizeHoldCodeEnum_virtual,
      _$organizeHoldCodeEnum_bookHeld,
      _$organizeHoldCodeEnum_readOnly,
      _$organizeHoldCodeEnum_movedSince,
      _$organizeHoldCodeEnum_uncataloged,
      _$organizeHoldCodeEnum_unknownDefaultOpenApi,
    ]);

Serializer<OrganizeHoldCodeEnum> _$organizeHoldCodeEnumSerializer =
    _$OrganizeHoldCodeEnumSerializer();

class _$OrganizeHoldCodeEnumSerializer
    implements PrimitiveSerializer<OrganizeHoldCodeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'collision': 'collision',
    'occupied': 'occupied',
    'occupiedCase': 'occupied-case',
    'untagged': 'untagged',
    'missing': 'missing',
    'virtual': 'virtual',
    'bookHeld': 'book-held',
    'readOnly': 'read-only',
    'movedSince': 'moved-since',
    'uncataloged': 'uncataloged',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'collision': 'collision',
    'occupied': 'occupied',
    'occupied-case': 'occupiedCase',
    'untagged': 'untagged',
    'missing': 'missing',
    'virtual': 'virtual',
    'book-held': 'bookHeld',
    'read-only': 'readOnly',
    'moved-since': 'movedSince',
    'uncataloged': 'uncataloged',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[OrganizeHoldCodeEnum];
  @override
  final String wireName = 'OrganizeHoldCodeEnum';

  @override
  Object serialize(
    Serializers serializers,
    OrganizeHoldCodeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  OrganizeHoldCodeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => OrganizeHoldCodeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$OrganizeHold extends OrganizeHold {
  @override
  final String? itemPid;
  @override
  final String from;
  @override
  final String? to;
  @override
  final OrganizeHoldCodeEnum code;
  @override
  final String reason;

  factory _$OrganizeHold([void Function(OrganizeHoldBuilder)? updates]) =>
      (OrganizeHoldBuilder()..update(updates))._build();

  _$OrganizeHold._({
    this.itemPid,
    required this.from,
    this.to,
    required this.code,
    required this.reason,
  }) : super._();
  @override
  OrganizeHold rebuild(void Function(OrganizeHoldBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OrganizeHoldBuilder toBuilder() => OrganizeHoldBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OrganizeHold &&
        itemPid == other.itemPid &&
        from == other.from &&
        to == other.to &&
        code == other.code &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, itemPid.hashCode);
    _$hash = $jc(_$hash, from.hashCode);
    _$hash = $jc(_$hash, to.hashCode);
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OrganizeHold')
          ..add('itemPid', itemPid)
          ..add('from', from)
          ..add('to', to)
          ..add('code', code)
          ..add('reason', reason))
        .toString();
  }
}

class OrganizeHoldBuilder
    implements Builder<OrganizeHold, OrganizeHoldBuilder> {
  _$OrganizeHold? _$v;

  String? _itemPid;
  String? get itemPid => _$this._itemPid;
  set itemPid(String? itemPid) => _$this._itemPid = itemPid;

  String? _from;
  String? get from => _$this._from;
  set from(String? from) => _$this._from = from;

  String? _to;
  String? get to => _$this._to;
  set to(String? to) => _$this._to = to;

  OrganizeHoldCodeEnum? _code;
  OrganizeHoldCodeEnum? get code => _$this._code;
  set code(OrganizeHoldCodeEnum? code) => _$this._code = code;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  OrganizeHoldBuilder() {
    OrganizeHold._defaults(this);
  }

  OrganizeHoldBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _itemPid = $v.itemPid;
      _from = $v.from;
      _to = $v.to;
      _code = $v.code;
      _reason = $v.reason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OrganizeHold other) {
    _$v = other as _$OrganizeHold;
  }

  @override
  void update(void Function(OrganizeHoldBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OrganizeHold build() => _build();

  _$OrganizeHold _build() {
    final _$result =
        _$v ??
        _$OrganizeHold._(
          itemPid: itemPid,
          from: BuiltValueNullFieldError.checkNotNull(
            from,
            r'OrganizeHold',
            'from',
          ),
          to: to,
          code: BuiltValueNullFieldError.checkNotNull(
            code,
            r'OrganizeHold',
            'code',
          ),
          reason: BuiltValueNullFieldError.checkNotNull(
            reason,
            r'OrganizeHold',
            'reason',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
