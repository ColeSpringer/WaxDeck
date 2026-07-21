// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credits_edit.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreditsEdit extends CreditsEdit {
  @override
  final String role;
  @override
  final BuiltList<String> names;
  @override
  final bool? writeBack;
  @override
  final bool? lock;
  @override
  final bool? force;

  factory _$CreditsEdit([void Function(CreditsEditBuilder)? updates]) =>
      (CreditsEditBuilder()..update(updates))._build();

  _$CreditsEdit._({
    required this.role,
    required this.names,
    this.writeBack,
    this.lock,
    this.force,
  }) : super._();
  @override
  CreditsEdit rebuild(void Function(CreditsEditBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreditsEditBuilder toBuilder() => CreditsEditBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreditsEdit &&
        role == other.role &&
        names == other.names &&
        writeBack == other.writeBack &&
        lock == other.lock &&
        force == other.force;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, role.hashCode);
    _$hash = $jc(_$hash, names.hashCode);
    _$hash = $jc(_$hash, writeBack.hashCode);
    _$hash = $jc(_$hash, lock.hashCode);
    _$hash = $jc(_$hash, force.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreditsEdit')
          ..add('role', role)
          ..add('names', names)
          ..add('writeBack', writeBack)
          ..add('lock', lock)
          ..add('force', force))
        .toString();
  }
}

class CreditsEditBuilder implements Builder<CreditsEdit, CreditsEditBuilder> {
  _$CreditsEdit? _$v;

  String? _role;
  String? get role => _$this._role;
  set role(String? role) => _$this._role = role;

  ListBuilder<String>? _names;
  ListBuilder<String> get names => _$this._names ??= ListBuilder<String>();
  set names(ListBuilder<String>? names) => _$this._names = names;

  bool? _writeBack;
  bool? get writeBack => _$this._writeBack;
  set writeBack(bool? writeBack) => _$this._writeBack = writeBack;

  bool? _lock;
  bool? get lock => _$this._lock;
  set lock(bool? lock) => _$this._lock = lock;

  bool? _force;
  bool? get force => _$this._force;
  set force(bool? force) => _$this._force = force;

  CreditsEditBuilder() {
    CreditsEdit._defaults(this);
  }

  CreditsEditBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _role = $v.role;
      _names = $v.names.toBuilder();
      _writeBack = $v.writeBack;
      _lock = $v.lock;
      _force = $v.force;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreditsEdit other) {
    _$v = other as _$CreditsEdit;
  }

  @override
  void update(void Function(CreditsEditBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreditsEdit build() => _build();

  _$CreditsEdit _build() {
    _$CreditsEdit _$result;
    try {
      _$result =
          _$v ??
          _$CreditsEdit._(
            role: BuiltValueNullFieldError.checkNotNull(
              role,
              r'CreditsEdit',
              'role',
            ),
            names: names.build(),
            writeBack: writeBack,
            lock: lock,
            force: force,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'names';
        names.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
          r'CreditsEdit',
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
