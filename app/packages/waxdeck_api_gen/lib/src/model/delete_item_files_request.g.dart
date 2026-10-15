// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delete_item_files_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DeleteItemFilesRequestModeEnum _$deleteItemFilesRequestModeEnum_trash =
    const DeleteItemFilesRequestModeEnum._('trash');
const DeleteItemFilesRequestModeEnum
_$deleteItemFilesRequestModeEnum_permanent =
    const DeleteItemFilesRequestModeEnum._('permanent');
const DeleteItemFilesRequestModeEnum
_$deleteItemFilesRequestModeEnum_unknownDefaultOpenApi =
    const DeleteItemFilesRequestModeEnum._('unknownDefaultOpenApi');

DeleteItemFilesRequestModeEnum _$deleteItemFilesRequestModeEnumValueOf(
  String name,
) {
  switch (name) {
    case 'trash':
      return _$deleteItemFilesRequestModeEnum_trash;
    case 'permanent':
      return _$deleteItemFilesRequestModeEnum_permanent;
    case 'unknownDefaultOpenApi':
      return _$deleteItemFilesRequestModeEnum_unknownDefaultOpenApi;
    default:
      return _$deleteItemFilesRequestModeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<DeleteItemFilesRequestModeEnum>
_$deleteItemFilesRequestModeEnumValues =
    BuiltSet<DeleteItemFilesRequestModeEnum>(
      const <DeleteItemFilesRequestModeEnum>[
        _$deleteItemFilesRequestModeEnum_trash,
        _$deleteItemFilesRequestModeEnum_permanent,
        _$deleteItemFilesRequestModeEnum_unknownDefaultOpenApi,
      ],
    );

Serializer<DeleteItemFilesRequestModeEnum>
_$deleteItemFilesRequestModeEnumSerializer =
    _$DeleteItemFilesRequestModeEnumSerializer();

class _$DeleteItemFilesRequestModeEnumSerializer
    implements PrimitiveSerializer<DeleteItemFilesRequestModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'trash': 'trash',
    'permanent': 'permanent',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'trash': 'trash',
    'permanent': 'permanent',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[DeleteItemFilesRequestModeEnum];
  @override
  final String wireName = 'DeleteItemFilesRequestModeEnum';

  @override
  Object serialize(
    Serializers serializers,
    DeleteItemFilesRequestModeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  DeleteItemFilesRequestModeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => DeleteItemFilesRequestModeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$DeleteItemFilesRequest extends DeleteItemFilesRequest {
  @override
  final BuiltList<String> filePids;
  @override
  final DeleteItemFilesRequestModeEnum? mode;
  @override
  final bool? dryRun;

  factory _$DeleteItemFilesRequest([
    void Function(DeleteItemFilesRequestBuilder)? updates,
  ]) => (DeleteItemFilesRequestBuilder()..update(updates))._build();

  _$DeleteItemFilesRequest._({required this.filePids, this.mode, this.dryRun})
    : super._();
  @override
  DeleteItemFilesRequest rebuild(
    void Function(DeleteItemFilesRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  DeleteItemFilesRequestBuilder toBuilder() =>
      DeleteItemFilesRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeleteItemFilesRequest &&
        filePids == other.filePids &&
        mode == other.mode &&
        dryRun == other.dryRun;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, filePids.hashCode);
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, dryRun.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeleteItemFilesRequest')
          ..add('filePids', filePids)
          ..add('mode', mode)
          ..add('dryRun', dryRun))
        .toString();
  }
}

class DeleteItemFilesRequestBuilder
    implements Builder<DeleteItemFilesRequest, DeleteItemFilesRequestBuilder> {
  _$DeleteItemFilesRequest? _$v;

  ListBuilder<String>? _filePids;
  ListBuilder<String> get filePids =>
      _$this._filePids ??= ListBuilder<String>();
  set filePids(ListBuilder<String>? filePids) => _$this._filePids = filePids;

  DeleteItemFilesRequestModeEnum? _mode;
  DeleteItemFilesRequestModeEnum? get mode => _$this._mode;
  set mode(DeleteItemFilesRequestModeEnum? mode) => _$this._mode = mode;

  bool? _dryRun;
  bool? get dryRun => _$this._dryRun;
  set dryRun(bool? dryRun) => _$this._dryRun = dryRun;

  DeleteItemFilesRequestBuilder() {
    DeleteItemFilesRequest._defaults(this);
  }

  DeleteItemFilesRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _filePids = $v.filePids.toBuilder();
      _mode = $v.mode;
      _dryRun = $v.dryRun;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeleteItemFilesRequest other) {
    _$v = other as _$DeleteItemFilesRequest;
  }

  @override
  void update(void Function(DeleteItemFilesRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DeleteItemFilesRequest build() => _build();

  _$DeleteItemFilesRequest _build() {
    _$DeleteItemFilesRequest _$result;
    try {
      _$result =
          _$v ??
          _$DeleteItemFilesRequest._(
            filePids: filePids.build(),
            mode: mode,
            dryRun: dryRun,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'filePids';
        filePids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'DeleteItemFilesRequest',
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
