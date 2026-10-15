// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'set_item_kind_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SetItemKindRequestMediaTypeEnum _$setItemKindRequestMediaTypeEnum_music =
    const SetItemKindRequestMediaTypeEnum._('music');
const SetItemKindRequestMediaTypeEnum
_$setItemKindRequestMediaTypeEnum_audiobook =
    const SetItemKindRequestMediaTypeEnum._('audiobook');
const SetItemKindRequestMediaTypeEnum
_$setItemKindRequestMediaTypeEnum_unknownDefaultOpenApi =
    const SetItemKindRequestMediaTypeEnum._('unknownDefaultOpenApi');

SetItemKindRequestMediaTypeEnum _$setItemKindRequestMediaTypeEnumValueOf(
  String name,
) {
  switch (name) {
    case 'music':
      return _$setItemKindRequestMediaTypeEnum_music;
    case 'audiobook':
      return _$setItemKindRequestMediaTypeEnum_audiobook;
    case 'unknownDefaultOpenApi':
      return _$setItemKindRequestMediaTypeEnum_unknownDefaultOpenApi;
    default:
      return _$setItemKindRequestMediaTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<SetItemKindRequestMediaTypeEnum>
_$setItemKindRequestMediaTypeEnumValues =
    BuiltSet<SetItemKindRequestMediaTypeEnum>(
      const <SetItemKindRequestMediaTypeEnum>[
        _$setItemKindRequestMediaTypeEnum_music,
        _$setItemKindRequestMediaTypeEnum_audiobook,
        _$setItemKindRequestMediaTypeEnum_unknownDefaultOpenApi,
      ],
    );

Serializer<SetItemKindRequestMediaTypeEnum>
_$setItemKindRequestMediaTypeEnumSerializer =
    _$SetItemKindRequestMediaTypeEnumSerializer();

class _$SetItemKindRequestMediaTypeEnumSerializer
    implements PrimitiveSerializer<SetItemKindRequestMediaTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'music': 'music',
    'audiobook': 'audiobook',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'music': 'music',
    'audiobook': 'audiobook',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[SetItemKindRequestMediaTypeEnum];
  @override
  final String wireName = 'SetItemKindRequestMediaTypeEnum';

  @override
  Object serialize(
    Serializers serializers,
    SetItemKindRequestMediaTypeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  SetItemKindRequestMediaTypeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => SetItemKindRequestMediaTypeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$SetItemKindRequest extends SetItemKindRequest {
  @override
  final BuiltList<String> pids;
  @override
  final SetItemKindRequestMediaTypeEnum mediaType;
  @override
  final bool? writeBack;

  factory _$SetItemKindRequest([
    void Function(SetItemKindRequestBuilder)? updates,
  ]) => (SetItemKindRequestBuilder()..update(updates))._build();

  _$SetItemKindRequest._({
    required this.pids,
    required this.mediaType,
    this.writeBack,
  }) : super._();
  @override
  SetItemKindRequest rebuild(
    void Function(SetItemKindRequestBuilder) updates,
  ) => (toBuilder()..update(updates)).build();

  @override
  SetItemKindRequestBuilder toBuilder() =>
      SetItemKindRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SetItemKindRequest &&
        pids == other.pids &&
        mediaType == other.mediaType &&
        writeBack == other.writeBack;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, pids.hashCode);
    _$hash = $jc(_$hash, mediaType.hashCode);
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SetItemKindRequest')
          ..add('pids', pids)
          ..add('mediaType', mediaType)
          ..add('writeBack', writeBack))
        .toString();
  }
}

class SetItemKindRequestBuilder
    implements Builder<SetItemKindRequest, SetItemKindRequestBuilder> {
  _$SetItemKindRequest? _$v;

  ListBuilder<String>? _pids;
  ListBuilder<String> get pids => _$this._pids ??= ListBuilder<String>();
  set pids(ListBuilder<String>? pids) => _$this._pids = pids;

  SetItemKindRequestMediaTypeEnum? _mediaType;
  SetItemKindRequestMediaTypeEnum? get mediaType => _$this._mediaType;
  set mediaType(SetItemKindRequestMediaTypeEnum? mediaType) =>
      _$this._mediaType = mediaType;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  SetItemKindRequestBuilder() {
    SetItemKindRequest._defaults(this);
  }

  SetItemKindRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _pids = $v.pids.toBuilder();
      _mediaType = $v.mediaType;
      _writeBack = $v.writeBack;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SetItemKindRequest other) {
    _$v = other as _$SetItemKindRequest;
  }

  @override
  void update(void Function(SetItemKindRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SetItemKindRequest build() => _build();

  _$SetItemKindRequest _build() {
    _$SetItemKindRequest _$result;
    try {
      _$result =
          _$v ??
          _$SetItemKindRequest._(
            pids: pids.build(),
            mediaType: BuiltValueNullFieldError.checkNotNull(
              mediaType,
              r'SetItemKindRequest',
              'mediaType',
            ),
            writeBack: writeBack,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'pids';
        pids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'SetItemKindRequest',
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
