// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'merge_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const MergeRequestEntityTypeEnum _$mergeRequestEntityTypeEnum_album =
    const MergeRequestEntityTypeEnum._('album');
const MergeRequestEntityTypeEnum _$mergeRequestEntityTypeEnum_artist =
    const MergeRequestEntityTypeEnum._('artist');
const MergeRequestEntityTypeEnum _$mergeRequestEntityTypeEnum_releaseGroup =
    const MergeRequestEntityTypeEnum._('releaseGroup');
const MergeRequestEntityTypeEnum _$mergeRequestEntityTypeEnum_genre =
    const MergeRequestEntityTypeEnum._('genre');
const MergeRequestEntityTypeEnum
_$mergeRequestEntityTypeEnum_unknownDefaultOpenApi =
    const MergeRequestEntityTypeEnum._('unknownDefaultOpenApi');

MergeRequestEntityTypeEnum _$mergeRequestEntityTypeEnumValueOf(String name) {
  switch (name) {
    case 'album':
      return _$mergeRequestEntityTypeEnum_album;
    case 'artist':
      return _$mergeRequestEntityTypeEnum_artist;
    case 'releaseGroup':
      return _$mergeRequestEntityTypeEnum_releaseGroup;
    case 'genre':
      return _$mergeRequestEntityTypeEnum_genre;
    case 'unknownDefaultOpenApi':
      return _$mergeRequestEntityTypeEnum_unknownDefaultOpenApi;
    default:
      return _$mergeRequestEntityTypeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<MergeRequestEntityTypeEnum> _$mergeRequestEntityTypeEnumValues =
    BuiltSet<MergeRequestEntityTypeEnum>(const <MergeRequestEntityTypeEnum>[
      _$mergeRequestEntityTypeEnum_album,
      _$mergeRequestEntityTypeEnum_artist,
      _$mergeRequestEntityTypeEnum_releaseGroup,
      _$mergeRequestEntityTypeEnum_genre,
      _$mergeRequestEntityTypeEnum_unknownDefaultOpenApi,
    ]);

Serializer<MergeRequestEntityTypeEnum> _$mergeRequestEntityTypeEnumSerializer =
    _$MergeRequestEntityTypeEnumSerializer();

class _$MergeRequestEntityTypeEnumSerializer
    implements PrimitiveSerializer<MergeRequestEntityTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'album': 'album',
    'artist': 'artist',
    'releaseGroup': 'release-group',
    'genre': 'genre',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'album': 'album',
    'artist': 'artist',
    'release-group': 'releaseGroup',
    'genre': 'genre',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[MergeRequestEntityTypeEnum];
  @override
  final String wireName = 'MergeRequestEntityTypeEnum';

  @override
  Object serialize(
    Serializers serializers,
    MergeRequestEntityTypeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  MergeRequestEntityTypeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => MergeRequestEntityTypeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$MergeRequest extends MergeRequest {
  @override
  final MergeRequestEntityTypeEnum entityType;
  @override
  final String survivorPid;
  @override
  final BuiltList<String> loserPids;

  factory _$MergeRequest([void Function(MergeRequestBuilder)? updates]) =>
      (MergeRequestBuilder()..update(updates))._build();

  _$MergeRequest._({
    required this.entityType,
    required this.survivorPid,
    required this.loserPids,
  }) : super._();
  @override
  MergeRequest rebuild(void Function(MergeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MergeRequestBuilder toBuilder() => MergeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MergeRequest &&
        entityType == other.entityType &&
        survivorPid == other.survivorPid &&
        loserPids == other.loserPids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entityType.hashCode);
    _$hash = $jc(_$hash, survivorPid.hashCode);
    _$hash = $jc(_$hash, loserPids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MergeRequest')
          ..add('entityType', entityType)
          ..add('survivorPid', survivorPid)
          ..add('loserPids', loserPids))
        .toString();
  }
}

class MergeRequestBuilder
    implements Builder<MergeRequest, MergeRequestBuilder> {
  _$MergeRequest? _$v;

  MergeRequestEntityTypeEnum? _entityType;
  MergeRequestEntityTypeEnum? get entityType => _$this._entityType;
  set entityType(MergeRequestEntityTypeEnum? entityType) =>
      _$this._entityType = entityType;

  String? _survivorPid;
  String? get survivorPid => _$this._survivorPid;
  set survivorPid(String? survivorPid) => _$this._survivorPid = survivorPid;

  ListBuilder<String>? _loserPids;
  ListBuilder<String> get loserPids =>
      _$this._loserPids ??= ListBuilder<String>();
  set loserPids(ListBuilder<String>? loserPids) =>
      _$this._loserPids = loserPids;

  MergeRequestBuilder() {
    MergeRequest._defaults(this);
  }

  MergeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entityType = $v.entityType;
      _survivorPid = $v.survivorPid;
      _loserPids = $v.loserPids.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MergeRequest other) {
    _$v = other as _$MergeRequest;
  }

  @override
  void update(void Function(MergeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MergeRequest build() => _build();

  _$MergeRequest _build() {
    _$MergeRequest _$result;
    try {
      _$result =
          _$v ??
          _$MergeRequest._(
            entityType: BuiltValueNullFieldError.checkNotNull(
              entityType,
              r'MergeRequest',
              'entityType',
            ),
            survivorPid: BuiltValueNullFieldError.checkNotNull(
              survivorPid,
              r'MergeRequest',
              'survivorPid',
            ),
            loserPids: loserPids.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'loserPids';
        loserPids.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'MergeRequest',
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
