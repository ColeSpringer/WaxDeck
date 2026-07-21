// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'locks_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LocksEdit extends LocksEdit {
  @override
  final BuiltList<String> fields;
  @override
  final bool locked;

  factory _$LocksEdit([void Function(LocksEditBuilder)? updates]) =>
      (LocksEditBuilder()..update(updates))._build();

  _$LocksEdit._({required this.fields, required this.locked}) : super._();
  @override
  LocksEdit rebuild(void Function(LocksEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LocksEditBuilder toBuilder() => LocksEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LocksEdit &&
        fields == other.fields &&
        locked == other.locked;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, fields.hashCode);
    _$hash = $jc(_$hash, locked.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LocksEdit')
          ..add('fields', fields)
          ..add('locked', locked))
        .toString();
  }
}

class LocksEditBuilder implements Builder<LocksEdit, LocksEditBuilder> {
  _$LocksEdit? _$v;

  ListBuilder<String>? _fields;
  ListBuilder<String> get fields => _$this._fields ??= ListBuilder<String>();
  set fields(ListBuilder<String>? fields) => _$this._fields = fields;

  bool? _locked;
  bool? get locked => _$this._locked;
  set locked(bool? locked) => _$this._locked = locked;

  LocksEditBuilder() {
    LocksEdit._defaults(this);
  }

  LocksEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _fields = $v.fields.toBuilder();
      _locked = $v.locked;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LocksEdit other) {
    _$v = other as _$LocksEdit;
  }

  @override
  void update(void Function(LocksEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LocksEdit build() => _build();

  _$LocksEdit _build() {
    _$LocksEdit _$result;
    try {
      _$result =
          _$v ??
          _$LocksEdit._(
            fields: fields.build(),
            locked: BuiltValueNullFieldError.checkNotNull(
              locked,
              r'LocksEdit',
              'locked',
            ),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'fields';
        fields.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'LocksEdit',
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
