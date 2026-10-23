// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'clear_finished_tasks_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ClearFinishedTasksRequestScopeEnum
_$clearFinishedTasksRequestScopeEnum_mine =
    const ClearFinishedTasksRequestScopeEnum._('mine');
const ClearFinishedTasksRequestScopeEnum
_$clearFinishedTasksRequestScopeEnum_all =
    const ClearFinishedTasksRequestScopeEnum._('all');
const ClearFinishedTasksRequestScopeEnum
_$clearFinishedTasksRequestScopeEnum_unknownDefaultOpenApi =
    const ClearFinishedTasksRequestScopeEnum._('unknownDefaultOpenApi');

ClearFinishedTasksRequestScopeEnum _$clearFinishedTasksRequestScopeEnumValueOf(
  String name,
) {
  switch (name) {
    case 'mine':
      return _$clearFinishedTasksRequestScopeEnum_mine;
    case 'all':
      return _$clearFinishedTasksRequestScopeEnum_all;
    case 'unknownDefaultOpenApi':
      return _$clearFinishedTasksRequestScopeEnum_unknownDefaultOpenApi;
    default:
      return _$clearFinishedTasksRequestScopeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<ClearFinishedTasksRequestScopeEnum>
_$clearFinishedTasksRequestScopeEnumValues =
    BuiltSet<ClearFinishedTasksRequestScopeEnum>(
      const <ClearFinishedTasksRequestScopeEnum>[
        _$clearFinishedTasksRequestScopeEnum_mine,
        _$clearFinishedTasksRequestScopeEnum_all,
        _$clearFinishedTasksRequestScopeEnum_unknownDefaultOpenApi,
      ],
    );

Serializer<ClearFinishedTasksRequestScopeEnum>
_$clearFinishedTasksRequestScopeEnumSerializer =
    _$ClearFinishedTasksRequestScopeEnumSerializer();

class _$ClearFinishedTasksRequestScopeEnumSerializer
    implements PrimitiveSerializer<ClearFinishedTasksRequestScopeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'mine': 'mine',
    'all': 'all',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'mine': 'mine',
    'all': 'all',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[ClearFinishedTasksRequestScopeEnum];
  @override
  final String wireName = 'ClearFinishedTasksRequestScopeEnum';

  @override
  Object serialize(
    Serializers serializers,
    ClearFinishedTasksRequestScopeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  ClearFinishedTasksRequestScopeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => ClearFinishedTasksRequestScopeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$ClearFinishedTasksRequest extends ClearFinishedTasksRequest {
  @override
  final ClearFinishedTasksRequestScopeEnum? scope;

  factory _$ClearFinishedTasksRequest([
    void Function(ClearFinishedTasksRequestBuilder)? updates,
  ]) => (ClearFinishedTasksRequestBuilder()..update(updates))._build();

  _$ClearFinishedTasksRequest._({this.scope}) : super._();
  @override
  ClearFinishedTasksRequest rebuild(
    void Function(ClearFinishedTasksRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  ClearFinishedTasksRequestBuilder toBuilder() =>
      ClearFinishedTasksRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ClearFinishedTasksRequest && scope == other.scope;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, scope.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'ClearFinishedTasksRequest',
    )..add('scope', scope)).toString();
  }
}

class ClearFinishedTasksRequestBuilder
    implements
        Builder<ClearFinishedTasksRequest, ClearFinishedTasksRequestBuilder> {
  _$ClearFinishedTasksRequest? _$v;

  ClearFinishedTasksRequestScopeEnum? _scope;
  ClearFinishedTasksRequestScopeEnum? get scope => _$this._scope;
  set scope(ClearFinishedTasksRequestScopeEnum? scope) => _$this._scope = scope;

  ClearFinishedTasksRequestBuilder() {
    ClearFinishedTasksRequest._defaults(this);
  }

  ClearFinishedTasksRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _scope = $v.scope;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ClearFinishedTasksRequest other) {
    _$v = other as _$ClearFinishedTasksRequest;
  }

  @override
  void update(void Function(ClearFinishedTasksRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ClearFinishedTasksRequest build() => _build();

  _$ClearFinishedTasksRequest _build() {
    final _$result = _$v ?? _$ClearFinishedTasksRequest._(scope: scope);
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
