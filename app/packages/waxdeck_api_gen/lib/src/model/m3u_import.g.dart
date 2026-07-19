// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'm3u_import.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$M3uImport extends M3uImport {
  @override
  final String name;
  @override
  final String? visibility;
  @override
  final String content;

  factory _$M3uImport([void Function(M3uImportBuilder)? updates]) =>
      (M3uImportBuilder()..update(updates))._build();

  _$M3uImport._({required this.name, this.visibility, required this.content})
    : super._();
  @override
  M3uImport rebuild(void Function(M3uImportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  M3uImportBuilder toBuilder() => M3uImportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is M3uImport &&
        name == other.name &&
        visibility == other.visibility &&
        content == other.content;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, visibility.hashCode);
    _$hash = $jc(_$hash, content.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'M3uImport')
          ..add('name', name)
          ..add('visibility', visibility)
          ..add('content', content))
        .toString();
  }
}

class M3uImportBuilder implements Builder<M3uImport, M3uImportBuilder> {
  _$M3uImport? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _visibility;
  String? get visibility => _$this._visibility;
  set visibility(String? visibility) => _$this._visibility = visibility;

  String? _content;
  String? get content => _$this._content;
  set content(String? content) => _$this._content = content;

  M3uImportBuilder() {
    M3uImport._defaults(this);
  }

  M3uImportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _visibility = $v.visibility;
      _content = $v.content;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(M3uImport other) {
    _$v = other as _$M3uImport;
  }

  @override
  void update(void Function(M3uImportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  M3uImport build() => _build();

  _$M3uImport _build() {
    final _$result =
        _$v ??
        _$M3uImport._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'M3uImport',
            'name',
          ),
          visibility: visibility,
          content: BuiltValueNullFieldError.checkNotNull(
            content,
            r'M3uImport',
            'content',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
