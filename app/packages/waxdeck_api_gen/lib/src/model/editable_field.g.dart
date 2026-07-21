// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'editable_field.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EditableField extends EditableField {
  @override
  final String name;
  @override
  final bool writeBack;

  factory _$EditableField([void Function(EditableFieldBuilder)? updates]) =>
      (EditableFieldBuilder()..update(updates))._build();

  _$EditableField._({required this.name, required this.writeBack}) : super._();
  @override
  EditableField rebuild(void Function(EditableFieldBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EditableFieldBuilder toBuilder() => EditableFieldBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EditableField &&
        name == other.name &&
        writeBack == other.writeBack;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EditableField')
          ..add('name', name)
          ..add('writeBack', writeBack))
        .toString();
  }
}

class EditableFieldBuilder
    implements Builder<EditableField, EditableFieldBuilder> {
  _$EditableField? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  EditableFieldBuilder() {
    EditableField._defaults(this);
  }

  EditableFieldBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _writeBack = $v.writeBack;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EditableField other) {
    _$v = other as _$EditableField;
  }

  @override
  void update(void Function(EditableFieldBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EditableField build() => _build();

  _$EditableField _build() {
    final _$result =
        _$v ??
        _$EditableField._(
          name: BuiltValueNullFieldError.checkNotNull(
            name,
            r'EditableField',
            'name',
          ),
          writeBack: BuiltValueNullFieldError.checkNotNull(
            writeBack,
            r'EditableField',
            'writeBack',
          ),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
