// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delete_items_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DeleteItemsRequestModeEnum _$deleteItemsRequestModeEnum_trash =
    const DeleteItemsRequestModeEnum._('trash');
const DeleteItemsRequestModeEnum _$deleteItemsRequestModeEnum_permanent =
    const DeleteItemsRequestModeEnum._('permanent');

DeleteItemsRequestModeEnum _$deleteItemsRequestModeEnumValueOf(String name) {
  switch (name) {
    case 'trash':
      return _$deleteItemsRequestModeEnum_trash;
    case 'permanent':
      return _$deleteItemsRequestModeEnum_permanent;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DeleteItemsRequestModeEnum> _$deleteItemsRequestModeEnumValues =
    BuiltSet<DeleteItemsRequestModeEnum>(const <DeleteItemsRequestModeEnum>[
      _$deleteItemsRequestModeEnum_trash,
      _$deleteItemsRequestModeEnum_permanent,
    ]);

Serializer<DeleteItemsRequestModeEnum> _$deleteItemsRequestModeEnumSerializer =
    _$DeleteItemsRequestModeEnumSerializer();

class _$DeleteItemsRequestModeEnumSerializer
    implements PrimitiveSerializer<DeleteItemsRequestModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'trash': 'trash',
    'permanent': 'permanent',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'trash': 'trash',
    'permanent': 'permanent',
  };

  @override
  final Iterable<Type> types = const <Type>[DeleteItemsRequestModeEnum];
  @override
  final String wireName = 'DeleteItemsRequestModeEnum';

  @override
  Object serialize(
    Serializers serializers,
    DeleteItemsRequestModeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  DeleteItemsRequestModeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => DeleteItemsRequestModeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$DeleteItemsRequest extends DeleteItemsRequest {
  @override
  final BuiltList<String> pids;
  @override
  final DeleteItemsRequestModeEnum? mode;
  @override
  final bool? dryRun;

  factory _$DeleteItemsRequest([
    void Function(DeleteItemsRequestBuilder)? updates,
  ]) => (DeleteItemsRequestBuilder()..update(updates))._build();

  _$DeleteItemsRequest._({required this.pids, this.mode, this.dryRun})
    : super._();
  @override
  DeleteItemsRequest rebuild(
    void Function(DeleteItemsRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  DeleteItemsRequestBuilder toBuilder() =>
      DeleteItemsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeleteItemsRequest &&
        pids == other.pids &&
        mode == other.mode &&
        dryRun == other.dryRun;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pids.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, dryRun.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeleteItemsRequest')
          ..add('pids', pids)
          ..add('mode', mode)
          ..add('dryRun', dryRun))
        .toString();
  }
}

class DeleteItemsRequestBuilder
    implements Builder<DeleteItemsRequest, DeleteItemsRequestBuilder> {
  _$DeleteItemsRequest? _$v;

  ListBuilder<String>? _pids;
  ListBuilder<String> get pids => _$this._pids ??= ListBuilder<String>();
  set pids(ListBuilder<String>? pids) => _$this._pids = pids;

  DeleteItemsRequestModeEnum? _mode;
  DeleteItemsRequestModeEnum? get mode => _$this._mode;
  set mode(DeleteItemsRequestModeEnum? mode) => _$this._mode = mode;

  bool? _dryRun;
  bool? get dryRun => _$this._dryRun;
  set dryRun(bool? dryRun) => _$this._dryRun = dryRun;

  DeleteItemsRequestBuilder() {
    DeleteItemsRequest._defaults(this);
  }

  DeleteItemsRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pids = $v.pids.toBuilder();
      _mode = $v.mode;
      _dryRun = $v.dryRun;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeleteItemsRequest other) {
    _$v = other as _$DeleteItemsRequest;
  }

  @override
  void update(void Function(DeleteItemsRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DeleteItemsRequest build() => _build();

  _$DeleteItemsRequest _build() {
    _$DeleteItemsRequest _$result;
    try {
      _$result =
          _$v ??
          _$DeleteItemsRequest._(
            pids: pids.build(),
            mode: mode,
            dryRun: dryRun,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pids';
        pids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'DeleteItemsRequest',
          _$failedField,
          e.toString(),
        );
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
