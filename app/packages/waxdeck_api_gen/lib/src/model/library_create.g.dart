// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_create.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const LibraryCreateMediaEnum _$libraryCreateMediaEnum_music =
    const LibraryCreateMediaEnum._('music');
const LibraryCreateMediaEnum _$libraryCreateMediaEnum_audiobook =
    const LibraryCreateMediaEnum._('audiobook');
const LibraryCreateMediaEnum _$libraryCreateMediaEnum_mixed =
    const LibraryCreateMediaEnum._('mixed');
const LibraryCreateMediaEnum _$libraryCreateMediaEnum_unknownDefaultOpenApi =
    const LibraryCreateMediaEnum._('unknownDefaultOpenApi');

LibraryCreateMediaEnum _$libraryCreateMediaEnumValueOf(String name) {
  switch (name) {
    case 'music':
      return _$libraryCreateMediaEnum_music;
    case 'audiobook':
      return _$libraryCreateMediaEnum_audiobook;
    case 'mixed':
      return _$libraryCreateMediaEnum_mixed;
    case 'unknownDefaultOpenApi':
      return _$libraryCreateMediaEnum_unknownDefaultOpenApi;
    default:
      return _$libraryCreateMediaEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<LibraryCreateMediaEnum> _$libraryCreateMediaEnumValues =
    BuiltSet<LibraryCreateMediaEnum>(const <LibraryCreateMediaEnum>[
      _$libraryCreateMediaEnum_music,
      _$libraryCreateMediaEnum_audiobook,
      _$libraryCreateMediaEnum_mixed,
      _$libraryCreateMediaEnum_unknownDefaultOpenApi,
    ]);

Serializer<LibraryCreateMediaEnum> _$libraryCreateMediaEnumSerializer =
    _$LibraryCreateMediaEnumSerializer();

class _$LibraryCreateMediaEnumSerializer
    implements PrimitiveSerializer<LibraryCreateMediaEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'music': 'music',
    'audiobook': 'audiobook',
    'mixed': 'mixed',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'music': 'music',
    'audiobook': 'audiobook',
    'mixed': 'mixed',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[LibraryCreateMediaEnum];
  @override
  final String wireName = 'LibraryCreateMediaEnum';

  @override
  Object serialize(
    Serializers serializers,
    LibraryCreateMediaEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  LibraryCreateMediaEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => LibraryCreateMediaEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$LibraryCreate extends LibraryCreate {
  @override
  final String name;
  @override
  final String path;
  @override
  final LibraryCreateMediaEnum? media;
  @override
  final bool? managed;

  factory _$LibraryCreate([void Function(LibraryCreateBuilder)? updates]) =>
      (LibraryCreateBuilder()..update(updates))._build();

  _$LibraryCreate._({
    required this.name,
    required this.path,
    this.media,
    this.managed,
  }) : super._();
  @override
  LibraryCreate rebuild(void Function(LibraryCreateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LibraryCreateBuilder toBuilder() => LibraryCreateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LibraryCreate &&
        name == other.name &&
        path == other.path &&
        media == other.media &&
        managed == other.managed;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, path.hashCode);
    _$hash = $jc(_$hash, media.hashCode);
    _$hash = $jc(_$hash, managed.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LibraryCreate')
          ..add('name', name)
          ..add('path', path)
          ..add('media', media)
          ..add('managed', managed))
        .toString();
  }
}

class LibraryCreateBuilder
    implements Builder<LibraryCreate, LibraryCreateBuilder> {
  _$LibraryCreate? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _path;
  String? get path => _$this._path;
  set path(String? path) => _$this._path = path;

  LibraryCreateMediaEnum? _media;
  LibraryCreateMediaEnum? get media => _$this._media;
  set media(LibraryCreateMediaEnum? media) => _$this._media = media;

  bool? _managed;
  bool? get managed => _$this._managed;
  set managed(bool? managed) => _$this._managed = managed;

  LibraryCreateBuilder() {
    LibraryCreate._defaults(this);
  }

  LibraryCreateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _path = $v.path;
      _media = $v.media;
      _managed = $v.managed;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LibraryCreate other) {
    _$v = other as _$LibraryCreate;
  }

  @override
  void update(void Function(LibraryCreateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LibraryCreate build() => _build();

  _$LibraryCreate _build() {
    final _$result =
        _$v ??
        _$LibraryCreate._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'LibraryCreate',
            'name',
          ),
          path: BuiltValueNullFieldError.checkNotNull(
            path,
            r'LibraryCreate',
            'path',
          ),
          media: media,
          managed: managed,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
