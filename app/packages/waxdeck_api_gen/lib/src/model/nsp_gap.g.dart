// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nsp_gap.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const NspGapKindEnum _$nspGapKindEnum_field = const NspGapKindEnum._('field');
const NspGapKindEnum _$nspGapKindEnum_operator_ = const NspGapKindEnum._(
  'operator_',
);
const NspGapKindEnum _$nspGapKindEnum_value = const NspGapKindEnum._('value');
const NspGapKindEnum _$nspGapKindEnum_shape = const NspGapKindEnum._('shape');
const NspGapKindEnum _$nspGapKindEnum_sort = const NspGapKindEnum._('sort');
const NspGapKindEnum _$nspGapKindEnum_limit = const NspGapKindEnum._('limit');
const NspGapKindEnum _$nspGapKindEnum_entity = const NspGapKindEnum._('entity');
const NspGapKindEnum _$nspGapKindEnum_malformed = const NspGapKindEnum._(
  'malformed',
);
const NspGapKindEnum _$nspGapKindEnum_unknownDefaultOpenApi =
    const NspGapKindEnum._('unknownDefaultOpenApi');

NspGapKindEnum _$nspGapKindEnumValueOf(String name) {
  switch (name) {
    case 'field':
      return _$nspGapKindEnum_field;
    case 'operator_':
      return _$nspGapKindEnum_operator_;
    case 'value':
      return _$nspGapKindEnum_value;
    case 'shape':
      return _$nspGapKindEnum_shape;
    case 'sort':
      return _$nspGapKindEnum_sort;
    case 'limit':
      return _$nspGapKindEnum_limit;
    case 'entity':
      return _$nspGapKindEnum_entity;
    case 'malformed':
      return _$nspGapKindEnum_malformed;
    case 'unknownDefaultOpenApi':
      return _$nspGapKindEnum_unknownDefaultOpenApi;
    default:
      return _$nspGapKindEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<NspGapKindEnum> _$nspGapKindEnumValues =
    BuiltSet<NspGapKindEnum>(const <NspGapKindEnum>[
      _$nspGapKindEnum_field,
      _$nspGapKindEnum_operator_,
      _$nspGapKindEnum_value,
      _$nspGapKindEnum_shape,
      _$nspGapKindEnum_sort,
      _$nspGapKindEnum_limit,
      _$nspGapKindEnum_entity,
      _$nspGapKindEnum_malformed,
      _$nspGapKindEnum_unknownDefaultOpenApi,
    ]);

Serializer<NspGapKindEnum> _$nspGapKindEnumSerializer =
    _$NspGapKindEnumSerializer();

class _$NspGapKindEnumSerializer
    implements PrimitiveSerializer<NspGapKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'field': 'field',
    'operator_': 'operator',
    'value': 'value',
    'shape': 'shape',
    'sort': 'sort',
    'limit': 'limit',
    'entity': 'entity',
    'malformed': 'malformed',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'field': 'field',
    'operator': 'operator_',
    'value': 'value',
    'shape': 'shape',
    'sort': 'sort',
    'limit': 'limit',
    'entity': 'entity',
    'malformed': 'malformed',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[NspGapKindEnum];
  @override
  final String wireName = 'NspGapKindEnum';

  @override
  Object serialize(
    Serializers serializers,
    NspGapKindEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  NspGapKindEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => NspGapKindEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$NspGap extends NspGap {
  @override
  final NspGapKindEnum kind;
  @override
  final String? field;
  @override
  final String? op;
  @override
  final JsonObject? value;
  @override
  final String path;
  @override
  final String reason;

  factory _$NspGap([void Function(NspGapBuilder)? updates]) =>
      (NspGapBuilder()..update(updates))._build();

  _$NspGap._({
    required this.kind,
    this.field,
    this.op,
    this.value,
    required this.path,
    required this.reason,
  }) : super._();
  @override
  NspGap rebuild(void Function(NspGapBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  NspGapBuilder toBuilder() => NspGapBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is NspGap &&
        kind == other.kind &&
        field == other.field &&
        op == other.op &&
        value == other.value &&
        path == other.path &&
        reason == other.reason;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, field.hashCode);
    _$hash = $jc(_$hash, op.hashCode);
    _$hash = $jc(_$hash, value.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, reason.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'NspGap')
          ..add('kind', kind)
          ..add('field', field)
          ..add('op', op)
          ..add('value', value)
          ..add('path', path)
          ..add('reason', reason))
        .toString();
  }
}

class NspGapBuilder implements Builder<NspGap, NspGapBuilder> {
  _$NspGap? _$v;

  NspGapKindEnum? _kind;
  NspGapKindEnum? get kind => _$this._kind;
  set kind(NspGapKindEnum? kind) => _$this._kind = kind;

  String? _field;
  String? get field => _$this._field;
  set field(String? field) => _$this._field = field;

  String? _op;
  String? get op => _$this._op;
  set op(String? op) => _$this._op = op;

  JsonObject? _value;
  JsonObject? get value => _$this._value;
  set value(JsonObject? value) => _$this._value = value;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  String? _reason;
  String? get reason => _$this._reason;
  set reason(String? reason) => _$this._reason = reason;

  NspGapBuilder() {
    NspGap._defaults(this);
  }

  NspGapBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _field = $v.field;
      _op = $v.op;
      _value = $v.value;
      _path = $v.path;
      _reason = $v.reason;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(NspGap other) {
    _$v = other as _$NspGap;
  }

  @override
  void update(void Function(NspGapBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  NspGap build() => _build();

  _$NspGap _build() {
    final _$result =
        _$v ??
        _$NspGap._(
          kind: BuiltValueNullFieldError.checkNotNull(kind, r'NspGap', 'kind'),
          field: field,
          op: op,
          value: value,
          path: BuiltValueNullFieldError.checkNotNull(path, r'NspGap', 'path'),
          reason: BuiltValueNullFieldError.checkNotNull(
            reason,
            r'NspGap',
            'reason',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
