// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'opml_import.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OpmlImport extends OpmlImport {
  @override
  final String opml;

  factory _$OpmlImport([void Function(OpmlImportBuilder)? updates]) =>
      (OpmlImportBuilder()..update(updates))._build();

  _$OpmlImport._({required this.opml}) : super._();
  @override
  OpmlImport rebuild(void Function(OpmlImportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OpmlImportBuilder toBuilder() => OpmlImportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OpmlImport && opml == other.opml;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, opml.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'OpmlImport',
    )..add('opml', opml)).toString();
  }
}

class OpmlImportBuilder implements Builder<OpmlImport, OpmlImportBuilder> {
  _$OpmlImport? _$v;

  String? _opml;
  String? get opml => _$this._opml;
  set opml(String? opml) => _$this._opml = opml;

  OpmlImportBuilder() {
    OpmlImport._defaults(this);
  }

  OpmlImportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _opml = $v.opml;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OpmlImport other) {
    _$v = other as _$OpmlImport;
  }

  @override
  void update(void Function(OpmlImportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OpmlImport build() => _build();

  _$OpmlImport _build() {
    final _$result =
        _$v ??
        _$OpmlImport._(
          opml: BuiltValueNullFieldError.checkNotNull(
            opml,
            r'OpmlImport',
            'opml',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
