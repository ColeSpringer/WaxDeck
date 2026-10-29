// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unfold_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const UnfoldRequestEntityTypeEnum _$unfoldRequestEntityTypeEnum_album =
    const UnfoldRequestEntityTypeEnum._('album');
const UnfoldRequestEntityTypeEnum _$unfoldRequestEntityTypeEnum_artist =
    const UnfoldRequestEntityTypeEnum._('artist');
const UnfoldRequestEntityTypeEnum _$unfoldRequestEntityTypeEnum_releaseGroup =
    const UnfoldRequestEntityTypeEnum._('releaseGroup');
const UnfoldRequestEntityTypeEnum _$unfoldRequestEntityTypeEnum_genre =
    const UnfoldRequestEntityTypeEnum._('genre');
const UnfoldRequestEntityTypeEnum _$unfoldRequestEntityTypeEnum_series =
    const UnfoldRequestEntityTypeEnum._('series');
const UnfoldRequestEntityTypeEnum
_$unfoldRequestEntityTypeEnum_unknownDefaultOpenApi =
    const UnfoldRequestEntityTypeEnum._('unknownDefaultOpenApi');

UnfoldRequestEntityTypeEnum _$unfoldRequestEntityTypeEnumValueOf(String name) {
  switch (name) {
    case 'album':
      return _$unfoldRequestEntityTypeEnum_album;
    case 'artist':
      return _$unfoldRequestEntityTypeEnum_artist;
    case 'releaseGroup':
      return _$unfoldRequestEntityTypeEnum_releaseGroup;
    case 'genre':
      return _$unfoldRequestEntityTypeEnum_genre;
    case 'series':
      return _$unfoldRequestEntityTypeEnum_series;
    case 'unknownDefaultOpenApi':
      return _$unfoldRequestEntityTypeEnum_unknownDefaultOpenApi;
    default:
      return _$unfoldRequestEntityTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<UnfoldRequestEntityTypeEnum>
_$unfoldRequestEntityTypeEnumValues =
    BuiltSet<UnfoldRequestEntityTypeEnum>(const <UnfoldRequestEntityTypeEnum>[
      _$unfoldRequestEntityTypeEnum_album,
      _$unfoldRequestEntityTypeEnum_artist,
      _$unfoldRequestEntityTypeEnum_releaseGroup,
      _$unfoldRequestEntityTypeEnum_genre,
      _$unfoldRequestEntityTypeEnum_series,
      _$unfoldRequestEntityTypeEnum_unknownDefaultOpenApi,
    ]);

Serializer<UnfoldRequestEntityTypeEnum>
_$unfoldRequestEntityTypeEnumSerializer =
    _$UnfoldRequestEntityTypeEnumSerializer();

class _$UnfoldRequestEntityTypeEnumSerializer
    implements PrimitiveSerializer<UnfoldRequestEntityTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'album': 'album',
    'artist': 'artist',
    'releaseGroup': 'release-group',
    'genre': 'genre',
    'series': 'series',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'album': 'album',
    'artist': 'artist',
    'release-group': 'releaseGroup',
    'genre': 'genre',
    'series': 'series',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[UnfoldRequestEntityTypeEnum];
  @override
  final String wireName = 'UnfoldRequestEntityTypeEnum';

  @override
  Object serialize(
    Serializers serializers,
    UnfoldRequestEntityTypeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  UnfoldRequestEntityTypeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => UnfoldRequestEntityTypeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$UnfoldRequest extends UnfoldRequest {
  @override
  final UnfoldRequestEntityTypeEnum entityType;
  @override
  final BuiltList<String> keys;

  factory _$UnfoldRequest([void Function(UnfoldRequestBuilder)? updates]) =>
      (UnfoldRequestBuilder()..update(updates))._build();

  _$UnfoldRequest._({required this.entityType, required this.keys}) : super._();
  @override
  UnfoldRequest rebuild(void Function(UnfoldRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UnfoldRequestBuilder toBuilder() => UnfoldRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UnfoldRequest &&
        entityType == other.entityType &&
        keys == other.keys;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entityType.hashCode);
    _$hash = $jc(_$hash, keys.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UnfoldRequest')
          ..add('entityType', entityType)
          ..add('keys', keys))
        .toString();
  }
}

class UnfoldRequestBuilder
    implements Builder<UnfoldRequest, UnfoldRequestBuilder> {
  _$UnfoldRequest? _$v;

  UnfoldRequestEntityTypeEnum? _entityType;
  UnfoldRequestEntityTypeEnum? get entityType => _$this._entityType;
  set entityType(UnfoldRequestEntityTypeEnum? entityType) =>
      _$this._entityType = entityType;

  ListBuilder<String>? _keys;
  ListBuilder<String> get keys => _$this._keys ??= ListBuilder<String>();
  set keys(ListBuilder<String>? keys) => _$this._keys = keys;

  UnfoldRequestBuilder() {
    UnfoldRequest._defaults(this);
  }

  UnfoldRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entityType = $v.entityType;
      _keys = $v.keys.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UnfoldRequest other) {
    _$v = other as _$UnfoldRequest;
  }

  @override
  void update(void Function(UnfoldRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UnfoldRequest build() => _build();

  _$UnfoldRequest _build() {
    _$UnfoldRequest _$result;
    try {
      _$result =
          _$v ??
          _$UnfoldRequest._(
            entityType: BuiltValueNullFieldError.checkNotNull(
              entityType,
              r'UnfoldRequest',
              'entityType',
            ),
            keys: keys.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'keys';
        keys.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'UnfoldRequest',
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
