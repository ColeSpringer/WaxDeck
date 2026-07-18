// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'libraries.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$Libraries extends Libraries {
  @override
  final BuiltList<ModelLibrary> libraries;

  factory _$Libraries([void Function(LibrariesBuilder)? updates]) =>
      (LibrariesBuilder()..update(updates))._build();

  _$Libraries._({required this.libraries}) : super._();
  @override
  Libraries rebuild(void Function(LibrariesBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LibrariesBuilder toBuilder() => LibrariesBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is Libraries && libraries == other.libraries;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, libraries.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'Libraries',
    )..add('libraries', libraries)).toString();
  }
}

class LibrariesBuilder implements Builder<Libraries, LibrariesBuilder> {
  _$Libraries? _$v;

  ListBuilder<ModelLibrary>? _libraries;
  ListBuilder<ModelLibrary> get libraries =>
      _$this._libraries ??= ListBuilder<ModelLibrary>();
  set libraries(ListBuilder<ModelLibrary>? libraries) =>
      _$this._libraries = libraries;

  LibrariesBuilder() {
    Libraries._defaults(this);
  }

  LibrariesBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _libraries = $v.libraries.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(Libraries other) {
    _$v = other as _$Libraries;
  }

  @override
  void update(void Function(LibrariesBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  Libraries build() => _build();

  _$Libraries _build() {
    _$Libraries _$result;
    try {
      _$result = _$v ?? _$Libraries._(libraries: libraries.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'libraries';
        libraries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'Libraries',
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
