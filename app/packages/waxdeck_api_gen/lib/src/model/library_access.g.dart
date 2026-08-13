// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_access.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const LibraryAccessModeEnum _$libraryAccessModeEnum_all =
    const LibraryAccessModeEnum._('all');
const LibraryAccessModeEnum _$libraryAccessModeEnum_granted =
    const LibraryAccessModeEnum._('granted');
const LibraryAccessModeEnum _$libraryAccessModeEnum_unknownDefaultOpenApi =
    const LibraryAccessModeEnum._('unknownDefaultOpenApi');

LibraryAccessModeEnum _$libraryAccessModeEnumValueOf(String name) {
  switch (name) {
    case 'all':
      return _$libraryAccessModeEnum_all;
    case 'granted':
      return _$libraryAccessModeEnum_granted;
    case 'unknownDefaultOpenApi':
      return _$libraryAccessModeEnum_unknownDefaultOpenApi;
    default:
      return _$libraryAccessModeEnum_unknownDefaultOpenApi;
  }
}

final BuiltSet<LibraryAccessModeEnum> _$libraryAccessModeEnumValues =
    BuiltSet<LibraryAccessModeEnum>(const <LibraryAccessModeEnum>[
      _$libraryAccessModeEnum_all,
      _$libraryAccessModeEnum_granted,
      _$libraryAccessModeEnum_unknownDefaultOpenApi,
    ]);

Serializer<LibraryAccessModeEnum> _$libraryAccessModeEnumSerializer =
    _$LibraryAccessModeEnumSerializer();

class _$LibraryAccessModeEnumSerializer
    implements PrimitiveSerializer<LibraryAccessModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'all': 'all',
    'granted': 'granted',
    'unknownDefaultOpenApi': 'unknown_default_open_api',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'all': 'all',
    'granted': 'granted',
    'unknown_default_open_api': 'unknownDefaultOpenApi',
  };

  @override
  final Iterable<Type> types = const <Type>[LibraryAccessModeEnum];
  @override
  final String wireName = 'LibraryAccessModeEnum';

  @override
  Object serialize(
    Serializers serializers,
    LibraryAccessModeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  LibraryAccessModeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => LibraryAccessModeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$LibraryAccess extends LibraryAccess {
  @override
  final LibraryAccessModeEnum mode;
  @override
  final BuiltList<String>? libraryPids;

  factory _$LibraryAccess([void Function(LibraryAccessBuilder)? updates]) =>
      (LibraryAccessBuilder()..update(updates))._build();

  _$LibraryAccess._({required this.mode, this.libraryPids}) : super._();
  @override
  LibraryAccess rebuild(void Function(LibraryAccessBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LibraryAccessBuilder toBuilder() => LibraryAccessBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LibraryAccess &&
        mode == other.mode &&
        libraryPids == other.libraryPids;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jc(_$hash, libraryPids.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LibraryAccess')
          ..add('mode', mode)
          ..add('libraryPids', libraryPids))
        .toString();
  }
}

class LibraryAccessBuilder
    implements Builder<LibraryAccess, LibraryAccessBuilder> {
  _$LibraryAccess? _$v;

  LibraryAccessModeEnum? _mode;
  LibraryAccessModeEnum? get mode => _$this._mode;
  set mode(LibraryAccessModeEnum? mode) => _$this._mode = mode;

  ListBuilder<String>? _libraryPids;
  ListBuilder<String> get libraryPids =>
      _$this._libraryPids ??= ListBuilder<String>();
  set libraryPids(ListBuilder<String>? libraryPids) =>
      _$this._libraryPids = libraryPids;

  LibraryAccessBuilder() {
    LibraryAccess._defaults(this);
  }

  LibraryAccessBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _mode = $v.mode;
      _libraryPids = $v.libraryPids?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LibraryAccess other) {
    _$v = other as _$LibraryAccess;
  }

  @override
  void update(void Function(LibraryAccessBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LibraryAccess build() => _build();

  _$LibraryAccess _build() {
    _$LibraryAccess _$result;
    try {
      _$result =
          _$v ??
          _$LibraryAccess._(
            mode: BuiltValueNullFieldError.checkNotNull(
              mode,
              r'LibraryAccess',
              'mode',
            ),
            libraryPids: _libraryPids?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'libraryPids';
        _libraryPids?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'LibraryAccess',
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
