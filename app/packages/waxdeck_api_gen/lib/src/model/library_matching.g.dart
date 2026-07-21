// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_matching.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const LibraryMatchingModeEnum _$libraryMatchingModeEnum_auto =
    const LibraryMatchingModeEnum._('auto');
const LibraryMatchingModeEnum _$libraryMatchingModeEnum_review =
    const LibraryMatchingModeEnum._('review');
const LibraryMatchingModeEnum _$libraryMatchingModeEnum_off =
    const LibraryMatchingModeEnum._('off');

LibraryMatchingModeEnum _$libraryMatchingModeEnumValueOf(String name) {
  switch (name) {
    case 'auto':
      return _$libraryMatchingModeEnum_auto;
    case 'review':
      return _$libraryMatchingModeEnum_review;
    case 'off':
      return _$libraryMatchingModeEnum_off;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<LibraryMatchingModeEnum> _$libraryMatchingModeEnumValues =
    BuiltSet<LibraryMatchingModeEnum>(const <LibraryMatchingModeEnum>[
      _$libraryMatchingModeEnum_auto,
      _$libraryMatchingModeEnum_review,
      _$libraryMatchingModeEnum_off,
    ]);

Serializer<LibraryMatchingModeEnum> _$libraryMatchingModeEnumSerializer =
    _$LibraryMatchingModeEnumSerializer();

class _$LibraryMatchingModeEnumSerializer
    implements PrimitiveSerializer<LibraryMatchingModeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'auto': 'auto',
    'review': 'review',
    'off': 'off',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'auto': 'auto',
    'review': 'review',
    'off': 'off',
  };

  @override
  final Iterable<Type> types = const <Type>[LibraryMatchingModeEnum];
  @override
  final String wireName = 'LibraryMatchingModeEnum';

  @override
  Object serialize(
    Serializers serializers,
    LibraryMatchingModeEnum object, {
    FullType specifiedType = FullType.unspecified,
  }) => _toWire[object.name] ?? object.name;

  @override
  LibraryMatchingModeEnum deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) => LibraryMatchingModeEnum.valueOf(
    _fromWire[serialized] ?? (serialized is String ? serialized : ''),
  );
}

class _$LibraryMatching extends LibraryMatching {
  @override
  final LibraryMatchingModeEnum mode;

  factory _$LibraryMatching([void Function(LibraryMatchingBuilder)? updates]) =>
      (LibraryMatchingBuilder()..update(updates))._build();

  _$LibraryMatching._({required this.mode}) : super._();
  @override
  LibraryMatching rebuild(void Function(LibraryMatchingBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LibraryMatchingBuilder toBuilder() => LibraryMatchingBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LibraryMatching && mode == other.mode;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, mode.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'LibraryMatching',
    )..add('mode', mode)).toString();
  }
}

class LibraryMatchingBuilder
    implements Builder<LibraryMatching, LibraryMatchingBuilder> {
  _$LibraryMatching? _$v;

  LibraryMatchingModeEnum? _mode;
  LibraryMatchingModeEnum? get mode => _$this._mode;
  set mode(LibraryMatchingModeEnum? mode) => _$this._mode = mode;

  LibraryMatchingBuilder() {
    LibraryMatching._defaults(this);
  }

  LibraryMatchingBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _mode = $v.mode;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LibraryMatching other) {
    _$v = other as _$LibraryMatching;
  }

  @override
  void update(void Function(LibraryMatchingBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LibraryMatching build() => _build();

  _$LibraryMatching _build() {
    final _$result =
        _$v ??
        _$LibraryMatching._(
          mode: BuiltValueNullFieldError.checkNotNull(
            mode,
            r'LibraryMatching',
            'mode',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
