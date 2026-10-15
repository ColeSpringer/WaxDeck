// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_media.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const LibraryMediaMediaEnum _$libraryMediaMediaEnum_music =
    const LibraryMediaMediaEnum._('music');
const LibraryMediaMediaEnum _$libraryMediaMediaEnum_audiobook =
    const LibraryMediaMediaEnum._('audiobook');
const LibraryMediaMediaEnum _$libraryMediaMediaEnum_mixed =
    const LibraryMediaMediaEnum._('mixed');
const LibraryMediaMediaEnum _$libraryMediaMediaEnum_unknownDefaultOpenApi =
    const LibraryMediaMediaEnum._('unknownDefaultOpenApi');

LibraryMediaMediaEnum _$libraryMediaMediaEnumValueOf(String name) {
  switch (name) {
    case 'music':
      return _$libraryMediaMediaEnum_music;
    case 'audiobook':
      return _$libraryMediaMediaEnum_audiobook;
    case 'mixed':
      return _$libraryMediaMediaEnum_mixed;
    case 'unknownDefaultOpenApi':
      return _$libraryMediaMediaEnum_unknownDefaultOpenApi;
    default:
      return _$libraryMediaMediaEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<LibraryMediaMediaEnum> _$libraryMediaMediaEnumValues =
    BuiltSet<LibraryMediaMediaEnum>(const <LibraryMediaMediaEnum>[
      _$libraryMediaMediaEnum_music,
      _$libraryMediaMediaEnum_audiobook,
      _$libraryMediaMediaEnum_mixed,
      _$libraryMediaMediaEnum_unknownDefaultOpenApi,
    ]);

Serializer<LibraryMediaMediaEnum> _$libraryMediaMediaEnumSerializer =
    _$LibraryMediaMediaEnumSerializer();

class _$LibraryMediaMediaEnumSerializer
    implements PrimitiveSerializer<LibraryMediaMediaEnum> {
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
  final Iterable<Type> types = const <Type>[LibraryMediaMediaEnum];
  @override
  final String wireName = 'LibraryMediaMediaEnum';

  @override
  Object serialize(
    Serializers serializers,
    LibraryMediaMediaEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  LibraryMediaMediaEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => LibraryMediaMediaEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$LibraryMedia extends LibraryMedia {
  @override
  final LibraryMediaMediaEnum media;

  factory _$LibraryMedia([void Function(LibraryMediaBuilder)? updates]) =>
      (LibraryMediaBuilder()..update(updates))._build();

  _$LibraryMedia._({required this.media}) : super._();
  @override
  LibraryMedia rebuild(void Function(LibraryMediaBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LibraryMediaBuilder toBuilder() => LibraryMediaBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LibraryMedia && media == other.media;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, media.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'LibraryMedia',
    )..add('media', media)).toString();
  }
}

class LibraryMediaBuilder
    implements Builder<LibraryMedia, LibraryMediaBuilder> {
  _$LibraryMedia? _$v;

  LibraryMediaMediaEnum? _media;
  LibraryMediaMediaEnum? get media => _$this._media;
  set media(LibraryMediaMediaEnum? media) => _$this._media = media;

  LibraryMediaBuilder() {
    LibraryMedia._defaults(this);
  }

  LibraryMediaBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _media = $v.media;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LibraryMedia other) {
    _$v = other as _$LibraryMedia;
  }

  @override
  void update(void Function(LibraryMediaBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LibraryMedia build() => _build();

  _$LibraryMedia _build() {
    final _$result =
        _$v ??
        _$LibraryMedia._(
          media: BuiltValueNullFieldError.checkNotNull(
            media,
            r'LibraryMedia',
            'media',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
