// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'locks_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LocksResult extends LocksResult {
  @override
  final BuiltList<String> lockedFields;

  factory _$LocksResult([void Function(LocksResultBuilder)? updates]) =>
      (LocksResultBuilder()..update(updates))._build();

  _$LocksResult._({required this.lockedFields}) : super._();
  @override
  LocksResult rebuild(void Function(LocksResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LocksResultBuilder toBuilder() => LocksResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LocksResult && lockedFields == other.lockedFields;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, lockedFields.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(
      r'LocksResult',
    )..add('lockedFields', lockedFields)).toString();
  }
}

class LocksResultBuilder implements Builder<LocksResult, LocksResultBuilder> {
  _$LocksResult? _$v;

  ListBuilder<String>? _lockedFields;
  ListBuilder<String> get lockedFields =>
      _$this._lockedFields ??= ListBuilder<String>();
  set lockedFields(ListBuilder<String>? lockedFields) =>
      _$this._lockedFields = lockedFields;

  LocksResultBuilder() {
    LocksResult._defaults(this);
  }

  LocksResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _lockedFields = $v.lockedFields.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LocksResult other) {
    _$v = other as _$LocksResult;
  }

  @override
  void update(void Function(LocksResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LocksResult build() => _build();

  _$LocksResult _build() {
    _$LocksResult _$result;
    try {
      _$result = _$v ?? _$LocksResult._(lockedFields: lockedFields.build());
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'lockedFields';
        lockedFields.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'LocksResult',
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
