// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$TagEdit extends TagEdit {
  @override
  final BuiltList<String> values;
  @override
  final bool? lock;
  @override
  final bool? force;

  factory _$TagEdit([void Function(TagEditBuilder)? updates]) =>
      (TagEditBuilder()..update(updates))._build();

  _$TagEdit._({required this.values, this.lock, this.force}) : super._();
  @override
  TagEdit rebuild(void Function(TagEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  TagEditBuilder toBuilder() => TagEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is TagEdit &&
        values == other.values &&
        lock == other.lock &&
        force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, values.hashCode);
    _$hash = $jc(_$hash, lock.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'TagEdit')
          ..add('values', values)
          ..add('lock', lock)
          ..add('force', force))
        .toString();
  }
}

class TagEditBuilder implements Builder<TagEdit, TagEditBuilder> {
  _$TagEdit? _$v;

  ListBuilder<String>? _values;
  ListBuilder<String> get values => _$this._values ??= ListBuilder<String>();
  set values(ListBuilder<String>? values) => _$this._values = values;

  bool? _lock;
  bool? get lock => _$this._lock;
  set lock(bool? lock) => _$this._lock = lock;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  TagEditBuilder() {
    TagEdit._defaults(this);
  }

  TagEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _values = $v.values.toBuilder();
      _lock = $v.lock;
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(TagEdit other) {
    _$v = other as _$TagEdit;
  }

  @override
  void update(void Function(TagEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  TagEdit build() => _build();

  _$TagEdit _build() {
    _$TagEdit _$result;
    try {
      _$result =
          _$v ?? _$TagEdit._(values: values.build(), lock: lock, force: force);
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'values';
        values.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'TagEdit',
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
